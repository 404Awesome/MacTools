import AppKit
import Combine
@preconcurrency import Dispatch
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// 主题配色管理：支持 macOS 明暗模式自适应
struct GH {
  static let light: [String: Color] = [
    "success": Color(hex: "16a34a"), "error": Color(hex: "dc2626"),
    "warning": Color(hex: "d97706"), "info": Color(hex: "2563eb"),
    "muted": Color(hex: "6b7280"), "fg": Color(hex: "111827"),
    "border": Color(hex: "e5e7eb"), "subtle": Color(hex: "f9fafb"),
    "accent": Color(hex: "2563eb"), "surface": Color(hex: "f3f4f6"),
  ]
  static let dark: [String: Color] = [
    "success": Color(hex: "4ade80"), "error": Color(hex: "f87171"),
    "warning": Color(hex: "fbbf24"), "info": Color(hex: "60a5fa"),
    "muted": Color(hex: "9ca3af"), "fg": Color(hex: "f3f4f6"),
    "border": Color(hex: "1e293b"), "subtle": Color(hex: "1e293b"),
    "accent": Color(hex: "60a5fa"), "surface": Color(hex: "1e293b"),
  ]
  static let adaptiveSuccess = Color.adaptive(light: light["success"]!, dark: dark["success"]!)
  static let adaptiveError = Color.adaptive(light: light["error"]!, dark: dark["error"]!)
  static let adaptiveWarning = Color.adaptive(light: light["warning"]!, dark: dark["warning"]!)
  static let adaptiveInfo = Color.adaptive(light: light["info"]!, dark: dark["info"]!)
  static let adaptiveMuted = Color.adaptive(light: light["muted"]!, dark: dark["muted"]!)
  static let adaptiveFg = Color.adaptive(light: light["fg"]!, dark: dark["fg"]!)
  static let adaptiveBorder = Color.adaptive(light: light["border"]!, dark: dark["border"]!)
  static let adaptiveSubtle = Color.adaptive(light: light["subtle"]!, dark: dark["subtle"]!)
  static let adaptiveAccent = Color.adaptive(light: light["accent"]!, dark: dark["accent"]!)
  static let adaptiveSurface = Color.adaptive(light: light["surface"]!, dark: dark["surface"]!)
}

extension Color {
  init(hex: String) {
    var i: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&i)
    self.init(
      .sRGB, red: Double(i >> 16 & 0xFF) / 255, green: Double(i >> 8 & 0xFF) / 255,
      blue: Double(i & 0xFF) / 255)
  }

  static func adaptive(light: Color, dark: Color) -> Color {
    Color(
      NSColor(
        name: nil,
        dynamicProvider: { appearance in
          let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
          let nsLight = NSColor(light)
          let nsDark = NSColor(dark)
          return isDark ? nsDark : nsLight
        }))
  }
}

// 日志级别，用于区分控制台输出的语义
enum LogLevel: String {
  case info, success, warning, error, command

  var color: Color {
    switch self {
    case .info: return GH.adaptiveMuted
    case .success: return GH.adaptiveSuccess
    case .warning: return GH.adaptiveWarning
    case .error: return GH.adaptiveError
    case .command: return GH.adaptiveInfo
    }
  }
}

// 单条日志记录，包含时间戳、级别与消息
struct LogEntry: Identifiable {
  let id = UUID()
  let timestamp = Date()
  let level: LogLevel
  let message: String

  static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
  }()

  static let periodFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "a"
    return f
  }()

  static let timeOnlyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm:ss"
    return f
  }()

  var timeString: String { Self.timeFormatter.string(from: timestamp) }
  var periodString: String { Self.periodFormatter.string(from: timestamp) }
  var timeOnlyString: String { Self.timeOnlyFormatter.string(from: timestamp) }
}

// 构建流程中的各个阶段，用于驱动进度条与状态展示
enum BuildStep: String, CaseIterable {
  case idle = "等待"
  case validating = "验证"
  case checkingEnv = "环境"
  case building = "打包"
  case deploying = "部署"
  case finished = "完成"
  case failed = "失败"
}

// 项目基本信息，由验证流程生成
struct ProjectInfo {
  let path: String, name: String, version: String, isValid: Bool, error: String?
}

// 构建与部署过程中可能遇到的错误类型
enum BuildError: LocalizedError {
  case projectInvalid(reason: String)
  case wpsjsNotFound
  case toolNotFound(tool: String, installHint: String)
  case buildFailed(exitCode: Int32)
  case cancelled
  case archiveNotFound
  case deploymentFailed(reason: String)
  case timeout

  var errorDescription: String? {
    switch self {
    case .projectInvalid(let reason): return "项目无效: \(reason)"
    case .wpsjsNotFound: return "未检测到 wpsjs 命令行工具"
    case .toolNotFound(let tool, let hint): return "缺少 \(tool) 工具，请安装: \(hint)"
    case .buildFailed(let code): return "构建失败，退出码: \(code)"
    case .cancelled: return "已取消"
    case .archiveNotFound: return "未找到构建产物"
    case .deploymentFailed(let reason): return "部署失败: \(reason)"
    case .timeout: return "操作超时"
    }
  }

  var isCancelled: Bool {
    if case .cancelled = self { return true }
    return false
  }
}

private let kLastPath = "com.exceltools.lastProjectPath"

// 核心构建服务：负责项目验证、调用 wpsjs 构建、产物查找与部署
final class WPSJSBuildService: @unchecked Sendable {
  nonisolated(unsafe) private var proc: Process?
  nonisolated(unsafe) private var isBuilding = false
  private let buildTimeout: TimeInterval = 300

  // 检查项目目录是否包含有效的 package.json
  func validateProject(_ path: String) -> ProjectInfo {
    let jsonPath = (path as NSString).appendingPathComponent("package.json")
    guard FileManager.default.fileExists(atPath: jsonPath) else {
      return ProjectInfo(
        path: path, name: "", version: "", isValid: false,
        error: BuildError.projectInvalid(reason: "缺少 package.json").localizedDescription)
    }
    do {
      let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      guard let name = json?["name"] as? String, !name.isEmpty else {
        return ProjectInfo(
          path: path, name: "", version: "", isValid: false,
          error: BuildError.projectInvalid(reason: "package.json 中缺少 name 字段").localizedDescription)
      }
      return ProjectInfo(
        path: path, name: name,
        version: json?["version"] as? String ?? "0.0.1", isValid: true, error: nil)
    } catch {
      return ProjectInfo(
        path: path, name: "", version: "", isValid: false,
        error: BuildError.projectInvalid(reason: "解析失败: \(error.localizedDescription)")
          .localizedDescription)
    }
  }

  // 在常见路径中查找 wpsjs 可执行文件
  func findWpsjs() -> [String] {
    ["/opt/homebrew/bin/wpsjs", "/usr/local/bin/wpsjs", "/usr/bin/wpsjs"]
      .filter { FileManager.default.isExecutableFile(atPath: $0) }
  }

  // 在常见路径中查找 7z 可执行文件
  func find7zPath() -> String? {
    let possiblePaths = [
      "/opt/homebrew/bin/7z",
      "/usr/local/bin/7z",
      "/usr/bin/7z",
    ]
    return possiblePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
  }

  // 执行 wpsjs build，实时通过 onLog 回调输出日志
  func build(_ projectPath: String, onLog: @escaping (LogEntry) -> Void) async -> Result<
    String, Error
  > {
    guard !isBuilding else {
      return .failure(BuildError.deploymentFailed(reason: "已有构建任务正在执行"))
    }

    let wpsjsPaths = findWpsjs()
    guard !wpsjsPaths.isEmpty else { return .failure(BuildError.wpsjsNotFound) }

    return await withCheckedContinuation { continuation in
      self.isBuilding = true
      let p = Process()
      self.proc = p
      let wpsjsPath = wpsjsPaths.first!
      let shellCmd = "printf '2\\n' | \"\(wpsjsPath)\" build 2>&1"
      p.executableURL = URL(fileURLWithPath: "/bin/bash")
      p.arguments = ["-c", shellCmd]
      p.currentDirectoryURL = URL(fileURLWithPath: projectPath)
      var env = ProcessInfo.processInfo.environment
      env["PATH"] =
        "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
      p.environment = env

      let pipe = Pipe()
      p.standardOutput = pipe
      p.standardError = pipe

      pipe.fileHandleForReading.readabilityHandler = { handle in
        guard let text = String(data: handle.availableData, encoding: .utf8), !text.isEmpty else {
          return
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
          let msg = String(line).trimmingCharacters(in: .whitespaces)
          guard !msg.isEmpty else { continue }
          let lower = msg.lowercased()
          let level: LogLevel
          if lower.contains("error") || lower.contains("fatal") {
            level = .error
          } else if lower.contains("success") || lower.contains("成功") || lower.contains("完毕") {
            level = .success
          } else if lower.contains("warn") {
            level = .warning
          } else if lower.contains("wpsjs") || lower.contains("build") {
            level = .command
          } else {
            level = .info
          }
          onLog(LogEntry(level: level, message: msg))
        }
      }

      final class TimeoutFlag: @unchecked Sendable {
        var timedOut = false
      }
      let timeoutFlag = TimeoutFlag()
      let timeoutItem = DispatchWorkItem { [weak self] in
        timeoutFlag.timedOut = true
        self?.proc?.terminate()
        self?.proc = nil
      }
      DispatchQueue.global().asyncAfter(deadline: .now() + buildTimeout, execute: timeoutItem)

      p.terminationHandler = { [weak self] _ in
        self?.isBuilding = false
        timeoutItem.cancel()
        self?.proc = nil
        pipe.fileHandleForReading.readabilityHandler = nil

        if timeoutFlag.timedOut {
          continuation.resume(returning: .failure(BuildError.timeout))
          return
        }

        let code = p.terminationStatus
        if code == 0 {
          let res = self?.findArchive(in: projectPath)
          switch res {
          case .success(let path):
            let name = (path as NSString).lastPathComponent
            onLog(LogEntry(level: .success, message: "构建完成，产物: \(name)"))
            continuation.resume(returning: .success(path))
          case .failure(let err): continuation.resume(returning: .failure(err))
          case .none: continuation.resume(returning: .failure(BuildError.archiveNotFound))
          }
        } else if code == 15 {
          continuation.resume(returning: .failure(BuildError.cancelled))
        } else {
          continuation.resume(returning: .failure(BuildError.buildFailed(exitCode: code)))
        }
      }
      do { try p.run() } catch {
        self.isBuilding = false
        timeoutItem.cancel()
        continuation.resume(returning: .failure(error))
      }
    }
  }

  func cancel() {
    proc?.terminate()
    proc = nil
    isBuilding = false
  }

  nonisolated private func findArchive(in path: String) -> Result<String, Error> {
    let fm = FileManager.default
    if let archive = findLatestArchive(in: path, fm: fm) { return .success(archive) }
    let buildDir = (path as NSString).appendingPathComponent("wps-addon-build")
    if fm.fileExists(atPath: buildDir) {
      if let archive = findLatestArchive(in: buildDir, fm: fm) { return .success(archive) }
      return .success(buildDir)
    }
    return .failure(BuildError.archiveNotFound)
  }

  nonisolated private func findLatestArchive(in dir: String, fm: FileManager) -> String? {
    guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return nil }
    let archives = items.filter { $0.hasSuffix(".7z") || $0.hasSuffix(".zip") }
      .map { (dir as NSString).appendingPathComponent($0) }
      .filter { fm.isReadableFile(atPath: $0) }
    return archives.max(by: {
      let d1 = (try? fm.attributesOfItem(atPath: $0)[.modificationDate] as? Date) ?? .distantPast
      let d2 = (try? fm.attributesOfItem(atPath: $1)[.modificationDate] as? Date) ?? .distantPast
      return d1 < d2
    })
  }

  // 将构建产物部署到 WPS 的 jsaddons 目录，支持回滚
  func deploy(output: String, info: ProjectInfo, onLog: @escaping (LogEntry) -> Void) async throws
    -> Bool
  {
    let jsaddons = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(
        "Library/Containers/com.kingsoft.wpsoffice.mac/Data/.kingsoft/wps/jsaddons")
    let fm = FileManager.default

    var backupPath: String?
    if fm.fileExists(atPath: jsaddons.path) {
      let backupDir = (NSTemporaryDirectory() as NSString).appendingPathComponent(
        "wpsjs_backup_\(UUID().uuidString)")
      do {
        try fm.copyItem(atPath: jsaddons.path, toPath: backupDir)
        backupPath = backupDir
        onLog(LogEntry(level: .info, message: "已创建备份: \(backupDir)"))
      } catch {
        onLog(LogEntry(level: .warning, message: "创建备份失败: \(error.localizedDescription)"))
      }
    }

    func rollback(_ message: String) throws {
      if let backup = backupPath, fm.fileExists(atPath: backup) {
        do {
          if fm.fileExists(atPath: jsaddons.path) {
            try fm.removeItem(atPath: jsaddons.path)
          }
          try fm.copyItem(atPath: backup, toPath: jsaddons.path)
          try fm.removeItem(atPath: backup)
          onLog(LogEntry(level: .warning, message: "已回滚到备份状态"))
        } catch {
          onLog(LogEntry(level: .error, message: "回滚失败: \(error.localizedDescription)"))
        }
      }
      throw BuildError.deploymentFailed(reason: message)
    }

    do {
      if fm.fileExists(atPath: jsaddons.path) {
        try clearDirectory(jsaddons.path)
        onLog(LogEntry(level: .info, message: "已清空 jsaddons 目录下所有内容"))
      }

      var isDir: ObjCBool = false
      let outputIsDir = fm.fileExists(atPath: output, isDirectory: &isDir) && isDir.boolValue

      if outputIsDir {
        onLog(LogEntry(level: .info, message: "产物为目录，直接部署内容"))
        let dirContents = try fm.contentsOfDirectory(atPath: output)
        for item in dirContents {
          let src = (output as NSString).appendingPathComponent(item)
          let dst = (jsaddons.path as NSString).appendingPathComponent(item)
          if fm.fileExists(atPath: dst) { try fm.removeItem(atPath: dst) }
          try fm.copyItem(atPath: src, toPath: dst)
        }
        onLog(LogEntry(level: .success, message: "部署完成"))
        cleanupBackup(backupPath)
        return true
      }

      if !fm.isReadableFile(atPath: output) {
        try rollback("压缩包不可读: \(output)")
      }

      let archiveName = (output as NSString).lastPathComponent
      let destArchive = (jsaddons.path as NSString).appendingPathComponent(archiveName)
      if fm.fileExists(atPath: destArchive) { try fm.removeItem(atPath: destArchive) }
      try fm.copyItem(atPath: output, toPath: destArchive)
      onLog(LogEntry(level: .info, message: "已复制压缩包至部署目录: \(archiveName)"))

      let ext = (archiveName as NSString).pathExtension.lowercased()

      let success: Bool
      if ext == "zip" || ext == "7z" {
        success = try unzipArchive(destArchive, to: jsaddons.path, onLog: onLog)
      } else {
        onLog(LogEntry(level: .success, message: "未知压缩格式，跳过解压"))
        cleanupBackup(backupPath)
        return true
      }

      if !success {
        try rollback("解压进程返回非零退出码")
      }

      let deployedContents = try fm.contentsOfDirectory(atPath: jsaddons.path)
        .filter { !$0.hasPrefix(".") }
      if deployedContents.isEmpty {
        try rollback("解压后目录为空，请检查压缩包内容")
      }

      let publishXml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <jsplugins>
          <jsplugin install="null" name="\(info.name)" enable="enable_dev" url="\(destArchive)" type="et" version="\(info.version)" customDomain=""/>
        </jsplugins>
        """
      let publishXmlPath = (jsaddons.path as NSString).appendingPathComponent("publish.xml")
      try publishXml.write(toFile: publishXmlPath, atomically: true, encoding: .utf8)
      onLog(LogEntry(level: .info, message: "已生成 publish.xml"))

      onLog(LogEntry(level: .success, message: "部署完成"))
      cleanupBackup(backupPath)
      return true
    } catch {
      cleanupBackup(backupPath)
      throw error
    }
  }

  private func cleanupBackup(_ backupPath: String?) {
    guard let path = backupPath else { return }
    try? FileManager.default.removeItem(atPath: path)
  }

  private func clearDirectory(_ path: String) throws {
    let fm = FileManager.default
    for item in try fm.contentsOfDirectory(atPath: path) {
      try fm.removeItem(atPath: (path as NSString).appendingPathComponent(item))
    }
  }

  private func unzipArchive(
    _ archivePath: String, to targetPath: String, onLog: @escaping (LogEntry) -> Void
  ) throws -> Bool {
    let ext = (archivePath as NSString).pathExtension.lowercased()
    if ext == "zip" {
      return try runTool(
        "/usr/bin/ditto", args: ["-x", "-k", archivePath, targetPath],
        toolName: "ditto", onLog: onLog)
    } else if ext == "7z" {
      guard let sevenZPath = find7zPath() else {
        throw BuildError.toolNotFound(tool: "7z", installHint: "brew install p7zip")
      }
      onLog(LogEntry(level: .info, message: "使用 7z 解压: \(sevenZPath)"))
      return try runTool(
        sevenZPath, args: ["x", archivePath, "-o\(targetPath)", "-y"],
        toolName: "7z", onLog: onLog)
    } else {
      throw BuildError.deploymentFailed(reason: "不支持的压缩格式: .\(ext)")
    }
  }

  private func runTool(
    _ path: String, args: [String], toolName: String, onLog: @escaping (LogEntry) -> Void
  ) throws -> Bool {
    let fm = FileManager.default
    guard fm.isExecutableFile(atPath: path) else {
      throw BuildError.toolNotFound(tool: toolName, installHint: "macOS 系统工具")
    }
    onLog(LogEntry(level: .info, message: "使用 \(toolName) 解压..."))

    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args

    let outPipe = Pipe()
    let errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe

    var outputData = Data()
    var errorData = Data()
    outPipe.fileHandleForReading.readabilityHandler = { outputData.append($0.availableData) }
    errPipe.fileHandleForReading.readabilityHandler = { errorData.append($0.availableData) }

    try p.run()
    p.waitUntilExit()

    outPipe.fileHandleForReading.readabilityHandler = nil
    errPipe.fileHandleForReading.readabilityHandler = nil

    if let text = String(data: outputData, encoding: .utf8), !text.isEmpty {
      for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let msg = String(line).trimmingCharacters(in: .whitespaces)
        if !msg.isEmpty { onLog(LogEntry(level: .info, message: msg)) }
      }
    }
    if let text = String(data: errorData, encoding: .utf8), !text.isEmpty {
      for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let msg = String(line).trimmingCharacters(in: .whitespaces)
        if !msg.isEmpty { onLog(LogEntry(level: .error, message: msg)) }
      }
    }

    let code = p.terminationStatus
    if code != 0 { onLog(LogEntry(level: .error, message: "\(toolName) 退出码: \(code)")) }
    return code == 0
  }

  // 清理构建临时目录
  func cleanBuildDir(projectPath: String, onLog: @escaping (LogEntry) -> Void) {
    let buildDir = (projectPath as NSString).appendingPathComponent("wps-addon-build")
    guard FileManager.default.fileExists(atPath: buildDir) else { return }
    do {
      try FileManager.default.removeItem(atPath: buildDir)
      onLog(LogEntry(level: .info, message: "已清理构建临时目录"))
    } catch {
      onLog(LogEntry(level: .warning, message: "清理临时目录失败"))
    }
  }

  // WPS 插件部署目录路径
  var jsaddonsPath: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(
        "Library/Containers/com.kingsoft.wpsoffice.mac/Data/.kingsoft/wps/jsaddons")
  }

  // 清空部署目录，用于开发模式或重置环境
  func clearDeployDirectory(onLog: @escaping (LogEntry) -> Void) throws {
    let fm = FileManager.default
    let path = jsaddonsPath.path
    guard fm.fileExists(atPath: path) else {
      onLog(LogEntry(level: .info, message: "部署目录不存在，无需清理"))
      return
    }
    let contents = try fm.contentsOfDirectory(atPath: path)
    guard !contents.isEmpty else {
      onLog(LogEntry(level: .info, message: "部署目录已为空"))
      return
    }
    for item in contents {
      let itemPath = (path as NSString).appendingPathComponent(item)
      try fm.removeItem(atPath: itemPath)
      onLog(LogEntry(level: .info, message: "已删除: \(item)"))
    }
    onLog(LogEntry(level: .success, message: "部署目录已清空 (共 \(contents.count) 项)"))
  }
}

// 视图模型：管理项目状态、构建流程与日志
final class PluginLoadViewModel: ObservableObject {
  @Published var projectPath: String {
    didSet { UserDefaults.standard.set(projectPath, forKey: kLastPath) }
  }
  @Published var projectInfo: ProjectInfo?
  @Published var status = "拖拽文件夹到窗口，或点击下方按钮选择项目"
  @Published var isProcessing = false
  @Published var logs: [LogEntry] = []
  @Published var currentStep: BuildStep = .idle
  @Published var showClearConfirm = false
  @Published var showDevModeConfirm = false

  private let service = WPSJSBuildService()
  private var task: Task<Void, Never>?

  var canBuild: Bool { !isProcessing && !projectPath.isEmpty && (projectInfo?.isValid ?? false) }

  init() {
    let saved = UserDefaults.standard.string(forKey: kLastPath) ?? ""
    projectPath = saved
    if !saved.isEmpty {
      let info = service.validateProject(saved)
      projectInfo = info
      status = info.isValid ? "\(info.name) v\(info.version) — 就绪" : "\(info.error ?? "无效项目")"
    }
  }

  // 通过 NSOpenPanel 选择项目目录
  func selectDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "选择 wpsjs 项目"
    if panel.runModal() == .OK, let url = panel.url {
      loadProject(url.path)
    }
  }

  // 加载并验证指定路径的项目
  func loadProject(_ path: String) {
    projectPath = path
    logs.removeAll()
    currentStep = .idle
    let info = service.validateProject(path)
    projectInfo = info
    status = info.isValid ? "\(info.name) v\(info.version) — 就绪" : "\(info.error ?? "无效项目")"
  }

  // 启动完整的构建与部署流程
  func startBuild() {
    guard canBuild, let info = projectInfo else { return }
    isProcessing = true
    logs.removeAll()
    currentStep = .idle
    status = "构建中..."

    task = Task {
      @MainActor func update(
        status: String? = nil, step: BuildStep? = nil, processing: Bool? = nil,
        appending: [LogEntry] = []
      ) {
        if let s = status { self.status = s }
        if let st = step { self.currentStep = st }
        if let p = processing { self.isProcessing = p }
        self.logs.append(contentsOf: appending)
      }

      currentStep = .validating
      update(
        step: .validating,
        appending: [LogEntry(level: .success, message: "项目验证通过: \(info.name) v\(info.version)")])

      currentStep = .checkingEnv
      let paths = service.findWpsjs()
      guard !paths.isEmpty else {
        update(
          status: BuildError.wpsjsNotFound.localizedDescription, step: .failed, processing: false)
        return
      }
      update(appending: [LogEntry(level: .success, message: "环境检测通过")])

      currentStep = .building
      let result = await service.build(projectPath) { entry in
        Task { @MainActor in self.logs.append(entry) }
      }

      switch result {
      case .success(let output):
        let ext = (output as NSString).pathExtension.lowercased()
        if ext == "7z" && service.find7zPath() == nil {
          let msg = BuildError.toolNotFound(tool: "7z", installHint: "brew install p7zip")
            .localizedDescription
          update(
            status: msg, step: .failed, processing: false,
            appending: [LogEntry(level: .error, message: msg)])
          return
        }

        currentStep = .deploying
        do {
          let ok = try await service.deploy(output: output, info: info) { entry in
            Task { @MainActor in self.logs.append(entry) }
          }
          if ok {
            service.cleanBuildDir(projectPath: projectPath) { entry in
              Task { @MainActor in self.logs.append(entry) }
            }
          }
          update(
            status: ok
              ? "构建成功！请重启 WPS 加载插件"
              : BuildError.deploymentFailed(reason: "未知原因").localizedDescription,
            step: ok ? .finished : .failed,
            processing: false
          )
        } catch {
          update(status: "部署异常: \(error.localizedDescription)", step: .failed, processing: false)
        }

      case .failure(let error):
        let buildError = error as? BuildError
        update(
          status: buildError?.isCancelled == true ? "构建已取消" : error.localizedDescription,
          step: buildError?.isCancelled == true ? .idle : .failed,
          processing: false
        )
      }
    }
  }

  func cancelBuild() {
    service.cancel()
    task?.cancel()
    task = nil
    isProcessing = false
    status = BuildError.cancelled.localizedDescription
    currentStep = .idle
  }

  func clearLogs() { logs.removeAll() }

  // 注：当前 UI 未提供触发入口，保留以备扩展
  func confirmClearDeploy() {
    showClearConfirm = true
  }

  func executeClearDeploy() {
    logs.removeAll()
    currentStep = .deploying
    status = "正在清空部署目录..."
    task = Task {
      do {
        try service.clearDeployDirectory { entry in
          Task { @MainActor in self.logs.append(entry) }
        }
        await MainActor.run {
          isProcessing = false
          status = "部署目录已清空"
          currentStep = .finished
        }
      } catch {
        await MainActor.run {
          isProcessing = false
          status = "清空失败: \(error.localizedDescription)"
          currentStep = .failed
        }
      }
    }
  }

  func confirmDevMode() {
    showDevModeConfirm = true
  }

  // 清空部署目录并进入开发模式
  func enterDevMode() {
    showDevModeConfirm = false
    logs.removeAll()
    currentStep = .idle
    status = "正在进入开发模式..."
    isProcessing = true
    task = Task {
      do {
        try service.clearDeployDirectory { entry in
          Task { @MainActor in self.logs.append(entry) }
        }
        await MainActor.run {
          isProcessing = false
          status = "开发模式已开启，部署目录已清空"
          currentStep = .idle
        }
      } catch {
        await MainActor.run {
          isProcessing = false
          status = "进入开发模式失败: \(error.localizedDescription)"
          currentStep = .failed
        }
      }
    }
  }

  // 导出当前日志到文本文件
  func exportLogs() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.plainText]
    panel.nameFieldStringValue =
      "wpsjs_build_log_\(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)).txt"
    panel.prompt = "导出日志"

    guard panel.runModal() == .OK, let url = panel.url else { return }

    let logContent = logs.map { entry in
      "[\(entry.timeString)] [\(entry.level.rawValue.uppercased())] \(entry.message)"
    }.joined(separator: "\n")

    do {
      try logContent.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      // 导出失败时静默处理，避免打断用户流程
    }
  }
}

// 主视图：左右分栏布局，左侧为项目信息与操作，右侧为构建日志
struct PluginLoad: View {
  @StateObject private var vm = PluginLoadViewModel()
  @State private var isTargeted = false

  var body: some View {
    ZStack {
      Color(red: 0.941, green: 0.945, blue: 0.957)
        .ignoresSafeArea()

      MovingGridLines(spacing: 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()

      HStack(spacing: 0) {
        leftPanel
        rightPanel
      }
      .frame(minWidth: 720, minHeight: 480)
      .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { handleDrop($0) }
      .overlay(dropOverlay)
    }
    .alert("进入开发模式", isPresented: $vm.showDevModeConfirm) {
      Button("取消", role: .cancel) {}
      Button("确认清空", role: .destructive) { vm.enterDevMode() }
    } message: {
      Text("进入开发模式将清空部署目录下的所有插件文件，便于重新加载开发版本。此操作不可撤销。")
    }
  }

  private var leftPanel: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 0) {
          Text("WPSJS 构建中心")
            .font(.system(size: 17))
            .foregroundColor(GH.adaptiveFg)
          Text("离线打包 · 一键部署")
            .font(.system(size: 12))
            .foregroundColor(GH.adaptiveMuted)
        }
        Spacer()
      }
      .padding(.horizontal, 14)
      .padding(.bottom, 6)

      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 12) {
          projectCard
          horizontalProgressBar
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
      }

      Spacer()

      bottomActionBar
    }
    .frame(width: 270)
  }

  private var projectCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("项目")
          .font(.system(size: 13))
          .foregroundColor(GH.adaptiveMuted)
          .textCase(.uppercase)
        Spacer()
        if let info = vm.projectInfo, info.isValid {
          HStack(spacing: 4) {
            Circle()
              .fill(GH.adaptiveSuccess)
              .frame(width: 5, height: 5)
            Text("已验证")
              .font(.system(size: 12))
              .foregroundColor(GH.adaptiveSuccess)
          }
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background(GH.adaptiveSuccess.opacity(0.1))
          .clipShape(Capsule())
        }
      }

      if let info = vm.projectInfo, info.isValid {
        HStack(spacing: 8) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundColor(GH.adaptiveSuccess)
            .font(.system(size: 14))
          VStack(alignment: .leading, spacing: 1) {
            Text(info.name)
              .font(.system(size: 15))
              .foregroundColor(GH.adaptiveFg)
            Text("v\(info.version)")
              .font(.system(size: 13))
              .foregroundColor(GH.adaptiveMuted)
          }
          Spacer()
        }
        .padding(10)
        .background(GH.adaptiveSuccess.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
      } else if let info = vm.projectInfo, !info.isValid {
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.circle.fill")
            .foregroundColor(GH.adaptiveError)
            .font(.system(size: 14))
          Text(info.error ?? "项目无效")
            .font(.system(size: 14))
            .foregroundColor(GH.adaptiveError)
          Spacer()
        }
        .padding(10)
        .background(GH.adaptiveError.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }

      VStack(spacing: 6) {
        HStack(spacing: 6) {
          Image(systemName: "folder")
            .font(.system(size: 13))
            .foregroundColor(GH.adaptiveMuted)
          Text(
            vm.projectPath.isEmpty
              ? "拖拽或点击选择..." : (vm.projectPath as NSString).abbreviatingWithTildeInPath
          )
          .font(.system(size: 13))
          .lineLimit(1)
          .foregroundColor(vm.projectPath.isEmpty ? GH.adaptiveMuted : GH.adaptiveFg)
          Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(GH.adaptiveSurface)
        .clipShape(RoundedRectangle(cornerRadius: 6))

        Button(action: vm.selectDirectory) {
          HStack(spacing: 4) {
            Image(systemName: "folder.badge.plus").font(.system(size: 12))
            Text("选择目录").font(.system(size: 13))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(GH.adaptiveAccent)
        .disabled(vm.isProcessing)
        .clipShape(RoundedRectangle(cornerRadius: 6))
      }
    }
    .padding(12)
    .background(GH.adaptiveSubtle)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private var horizontalProgressBar: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("构建进度")
        .font(.system(size: 13))
        .foregroundColor(GH.adaptiveMuted)
        .textCase(.uppercase)

      StripedProgressBar(
        progress: progressFraction(),
        isFailed: vm.currentStep == .failed
      )
      .frame(height: 14)

      HStack(spacing: 0) {
        let steps = BuildStep.allCases.filter { $0 != .idle && $0 != .failed }
        ForEach(Array(steps.enumerated()), id: \.element) { index, step in
          Text(step.rawValue)
            .font(.system(size: 13, weight: isActive(step) ? .semibold : .regular))
            .foregroundColor(labelColor(step))
            .frame(maxWidth: .infinity)
        }
      }
    }
    .padding(12)
    .background(GH.adaptiveSubtle)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private func progressFraction() -> CGFloat {
    switch vm.currentStep {
    case .idle: return 0
    case .validating: return 0.25
    case .checkingEnv: return 0.5
    case .building: return 0.75
    case .deploying: return 0.9
    case .finished: return 1.0
    case .failed: return 0.85
    }
  }

  // 带动画条纹的进度条，使用 TimelineView 实现平滑循环
  private struct StripedProgressBar: View {
    let progress: CGFloat
    let isFailed: Bool

    var body: some View {
      TimelineView(.animation(minimumInterval: 1 / 60)) { context in
        GeometryReader { geo in
          let phase = Self.phase(for: context.date)
          ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
              .fill(GH.adaptiveBorder.opacity(0.2))

            RoundedRectangle(cornerRadius: 3)
              .fill(barColor)
              .frame(width: max(0, geo.size.width * progress))
              .overlay(
                DiagonalStripes()
                  .fill(.white.opacity(0.28))
                  .frame(width: geo.size.width + 60, height: geo.size.height)
                  .offset(x: phase)
              )
              .mask(
                RoundedRectangle(cornerRadius: 3)
                  .frame(width: max(0, geo.size.width * progress), height: geo.size.height)
              )
              .animation(.easeInOut(duration: 0.5), value: progress)
          }
          .clipShape(RoundedRectangle(cornerRadius: 3))
        }
      }
    }

    private var barColor: Color {
      isFailed ? GH.adaptiveError : GH.adaptiveSuccess
    }

    private static func phase(for date: Date) -> CGFloat {
      let duration: Double = 0.6
      let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
      return -(CGFloat(t) / CGFloat(duration)) * 20
    }
  }

  private struct DiagonalStripes: Shape {
    let stripeWidth: CGFloat = 10
    let spacing: CGFloat = 10

    func path(in rect: CGRect) -> Path {
      var path = Path()
      let totalW = rect.width + rect.height
      let count = Int(totalW / (stripeWidth + spacing)) + 5

      for i in 0..<count {
        let x = CGFloat(i) * (stripeWidth + spacing)
        path.move(to: CGPoint(x: x, y: rect.height))
        path.addLine(to: CGPoint(x: x + stripeWidth, y: rect.height))
        path.addLine(to: CGPoint(x: x + stripeWidth - rect.height, y: 0))
        path.addLine(to: CGPoint(x: x - rect.height, y: 0))
        path.closeSubpath()
      }
      return path
    }
  }

  private var bottomActionBar: some View {
    VStack(spacing: 0) {
      VStack(spacing: 10) {
        HStack(spacing: 8) {
          Circle()
            .fill(statusDot)
            .frame(width: 7, height: 7)
            .shadow(color: statusDot.opacity(0.4), radius: 3, x: 0, y: 0)
          Text(vm.status)
            .font(.system(size: 13))
            .foregroundColor(statusColor)
            .lineLimit(1)
          Spacer()
        }

        HStack(spacing: 8) {
          Button(action: vm.confirmDevMode) {
            HStack(spacing: 4) {
              Image(systemName: "flame.fill")
                .font(.system(size: 12))
              Text("开发模式")
                .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
          }
          .buttonStyle(.bordered)
          .tint(GH.adaptiveWarning)
          .disabled(vm.isProcessing)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .help("清空部署目录，进入开发调试模式")

          Button(action: vm.isProcessing ? vm.cancelBuild : vm.startBuild) {
            HStack(spacing: 4) {
              Image(systemName: vm.isProcessing ? "stop.fill" : "play.fill")
                .font(.system(size: 12))
              Text(vm.isProcessing ? "停止构建" : "开始打包")
                .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
          }
          .buttonStyle(.borderedProminent)
          .tint(vm.isProcessing ? GH.adaptiveError : GH.adaptiveSuccess)
          .disabled(!vm.canBuild && !vm.isProcessing)
          .clipShape(RoundedRectangle(cornerRadius: 8))
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 12)
    }
  }

  private var rightPanel: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Text("构建日志")
          .font(.system(size: 15))
          .foregroundColor(GH.adaptiveFg)
        Spacer()
        if !vm.logs.isEmpty {
          Text("\(vm.logs.count)")
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(GH.adaptiveMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(GH.adaptiveSurface)
            .clipShape(Capsule())

          Button(action: vm.clearLogs) {
            Image(systemName: "eraser")
              .font(.system(size: 13))
          }
          .buttonStyle(.borderless)
          .foregroundColor(GH.adaptiveMuted)
          .help("清空日志")

          Button(action: vm.exportLogs) {
            Image(systemName: "square.and.arrow.up")
              .font(.system(size: 13))
          }
          .buttonStyle(.borderless)
          .foregroundColor(GH.adaptiveMuted)
          .help("导出日志")
        }
      }
      .padding(.horizontal, 14)
      .padding(.bottom, 6)

      ScrollViewReader { proxy in
        ScrollView(.vertical, showsIndicators: false) {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(vm.logs) { entry in
              logRow(entry).id(entry.id)
            }
            if vm.logs.isEmpty {
              emptyLogState
            }
            Color.clear.frame(height: 1).id("BOTTOM")
          }
          .padding(.vertical, 4)
        }
        .onChange(of: vm.logs.count) {
          withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("BOTTOM", anchor: .bottom)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func isDone(_ step: BuildStep) -> Bool {
    stepIdx(step) < stepIdx(vm.currentStep) && vm.currentStep != .failed
  }

  private func isActive(_ step: BuildStep) -> Bool {
    vm.currentStep == step
  }

  private func labelColor(_ step: BuildStep) -> Color {
    if isDone(step) || (vm.currentStep == .finished && step == .finished) {
      return GH.adaptiveSuccess
    }
    if isActive(step) { return GH.adaptiveFg }
    return GH.adaptiveMuted
  }

  private func stepIdx(_ step: BuildStep) -> Int { BuildStep.allCases.firstIndex(of: step) ?? 0 }

  private var emptyLogState: some View {
    VStack(spacing: 10) {
      Image(systemName: "terminal")
        .font(.system(size: 36))
        .foregroundColor(GH.adaptiveBorder)
      Text("等待任务启动...")
        .font(.system(size: 15))
        .foregroundColor(GH.adaptiveMuted)
      Text("拖拽项目文件夹到窗口即可快速加载")
        .font(.system(size: 13))
        .foregroundColor(GH.adaptiveMuted.opacity(0.6))
    }
    .padding(.top, 100)
    .frame(maxWidth: .infinity, alignment: .top)
  }

  private func logRow(_ entry: LogEntry) -> some View {
    HStack(alignment: .top, spacing: 0) {
      Rectangle()
        .fill(entry.level.color)
        .frame(width: 3)
        .padding(.vertical, 1)
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        VStack(alignment: .leading, spacing: 0) {
          Text(entry.periodString)
            .font(.system(size: 10))
            .foregroundColor(GH.adaptiveMuted.opacity(0.5))
            .lineLimit(1)
          Text(entry.timeOnlyString)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(GH.adaptiveMuted.opacity(0.5))
            .lineLimit(1)
        }
        .frame(width: 60, alignment: .leading)

        Text(entry.message)
          .font(.system(size: 14, design: .monospaced))
          .foregroundColor(
            entry.level == .error
              ? GH.adaptiveError : (entry.level == .success ? GH.adaptiveSuccess : GH.adaptiveFg)
          )
          .textSelection(.enabled)
          .lineLimit(nil)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 5)
      Spacer()
    }
    .background(entry.level == .error ? GH.adaptiveError.opacity(0.04) : Color.clear)
    .contentShape(Rectangle())
  }

  private var dropOverlay: some View {
    Group {
      if isTargeted {
        RoundedRectangle(cornerRadius: 16)
          .stroke(GH.adaptiveAccent, style: StrokeStyle(lineWidth: 2, dash: [10, 5]))
          .background(GH.adaptiveAccent.opacity(0.05))
          .overlay(
            VStack(spacing: 12) {
              Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(GH.adaptiveAccent)
              Text("释放以加载项目")
                .font(.system(size: 17))
                .foregroundColor(GH.adaptiveAccent)
            }
          )
          .padding(12)
      }
    }
  }

  private var statusDot: Color {
    if vm.isProcessing { return GH.adaptiveWarning }
    if vm.currentStep == .finished { return GH.adaptiveSuccess }
    if vm.currentStep == .failed { return GH.adaptiveError }
    return GH.adaptiveBorder
  }

  private var statusColor: Color {
    let s = vm.status
    if s.contains("失败") || s.contains("错误") { return GH.adaptiveError }
    if s.contains("成功") || s.contains("已清空") || s.contains("开发模式") { return GH.adaptiveSuccess }
    if s.contains("取消") { return GH.adaptiveWarning }
    return GH.adaptiveMuted
  }

  private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
    guard let provider = providers.first else { return false }
    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
      guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil)
      else { return }
      DispatchQueue.main.async { vm.loadProject(url.path) }
    }
    return true
  }
}
