import AppKit
import Combine
import SwiftUI

// MARK: - Service（功能不变）

final class NoTunesService: ObservableObject {
  @Published var isEnabled = false
  @Published var blockCount = 0
  @Published var lastBlocked: Date?

  private let agentLabel = "com.mactools.blockmusic"
  private var launchObserver: NSObjectProtocol?

  var plistPath: String {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
      .path
  }

  var logPath: String {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/\(agentLabel).log")
      .path
  }

  func checkStatus() {
    isEnabled = FileManager.default.fileExists(atPath: plistPath) && isAgentLoaded()
  }

  private func isAgentLoaded() -> Bool {
    let task = Process()
    task.launchPath = "/bin/launchctl"
    task.arguments = ["list", agentLabel]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    do {
      try task.run()
      task.waitUntilExit()
      return task.terminationStatus == 0
    } catch {
      return false
    }
  }

  @discardableResult
  func toggle(enabled: Bool) -> Bool {
    if enabled {
      let ok = createAndLoadAgent()
      if ok {
        registerRealtimeObserver()
        terminateRunningMusicApps()
      }
      return ok
    } else {
      unregisterRealtimeObserver()
      return unloadAndRemoveAgent()
    }
  }

  private func registerRealtimeObserver() {
    guard launchObserver == nil else { return }
    launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didLaunchApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self = self else { return }
      guard
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication
      else { return }
      if let bundleId = app.bundleIdentifier,
        bundleId == "com.apple.Music" || bundleId == "com.apple.iTunes"
      {
        app.forceTerminate()
        let name = bundleId == "com.apple.Music" ? "Music" : "iTunes"
        self.logBlock(appName: name, source: "realtime")
      }
    }
  }

  private func unregisterRealtimeObserver() {
    if let observer = launchObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      launchObserver = nil
    }
  }

  private func terminateRunningMusicApps() {
    NSWorkspace.shared.runningApplications
      .filter { app in
        guard let bundleId = app.bundleIdentifier else { return false }
        return bundleId == "com.apple.Music" || bundleId == "com.apple.iTunes"
      }
      .forEach { $0.forceTerminate() }
  }

  private func createAndLoadAgent() -> Bool {
    let fm = FileManager.default
    let launchAgentsDir = (plistPath as NSString).deletingLastPathComponent

    if !fm.fileExists(atPath: launchAgentsDir) {
      do {
        try fm.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
      } catch {
        return false
      }
    }

    let logDir = (logPath as NSString).deletingLastPathComponent
    if !fm.fileExists(atPath: logDir) {
      try? fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)
    }

    let scriptContent = """
      while true; do
          PID=$(pgrep -x "Music")
          if [ -n "$PID" ]; then
              kill -9 "$PID"
              echo "$(date '+%Y-%m-%d %H:%M:%S') BLOCKED Music (agent)" >> \(logPath)
          fi
          ITUNES=$(pgrep -x "iTunes")
          if [ -n "$ITUNES" ]; then
              kill -9 "$ITUNES"
              echo "$(date '+%Y-%m-%d %H:%M:%S') BLOCKED iTunes (agent)" >> \(logPath)
          fi
          sleep 0.35
      done
      """

    let plistContent = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>Label</key>
          <string>\(agentLabel)</string>
          <key>ProgramArguments</key>
          <array>
              <string>/bin/sh</string>
              <string>-c</string>
              <string>\(scriptContent)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>/dev/null</string>
          <key>StandardErrorPath</key>
          <string>\(logPath)</string>
      </dict>
      </plist>
      """

    do {
      try plistContent.write(toFile: plistPath, atomically: true, encoding: String.Encoding.utf8)
    } catch {
      return false
    }

    let task = Process()
    task.launchPath = "/bin/launchctl"
    task.arguments = ["load", plistPath]

    do {
      try task.run()
      task.waitUntilExit()
      return task.terminationStatus == 0
    } catch {
      return false
    }
  }

  private func unloadAndRemoveAgent() -> Bool {
    let task = Process()
    task.launchPath = "/bin/launchctl"
    task.arguments = ["unload", plistPath]
    do {
      try task.run()
      task.waitUntilExit()
    } catch {
      // 即使 unload 失败也继续删除文件
    }

    do {
      try FileManager.default.removeItem(atPath: plistPath)
    } catch {
      return false
    }
    return true
  }

  private func logBlock(appName: String, source: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let timestamp = formatter.string(from: Date())
    let logLine = "\(timestamp) BLOCKED \(appName) (\(source))\n"

    if let data = logLine.data(using: .utf8) {
      if FileManager.default.fileExists(atPath: logPath) {
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
          _ = handle.seekToEndOfFile()
          handle.write(data)
          try? handle.close()
        }
      } else {
        try? logLine.write(toFile: logPath, atomically: true, encoding: .utf8)
      }
    }

    blockCount += 1
    lastBlocked = Date()
  }

  func loadStats() {
    guard FileManager.default.fileExists(atPath: logPath) else { return }
    do {
      let content = try String(contentsOfFile: logPath, encoding: .utf8)
      let lines = content.components(separatedBy: .newlines)
      let blockedLines = lines.filter { $0.contains("BLOCKED") }
      blockCount = blockedLines.count
      if let lastLine = blockedLines.last {
        let dateStr = lastLine.prefix(19)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        lastBlocked = formatter.date(from: String(dateStr))
      }
    } catch {
      // ignore
    }
  }
}

// MARK: - View

struct NoTunesAgent: View {
  @StateObject private var service = NoTunesService()
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var showError = false

  @State private var typedTitle = ""
  @State private var showCursor = true
  private let fullTitle = "禁用音乐"

  private let cText = Color(red: 0.067, green: 0.067, blue: 0.153)
  private let cMuted = Color(red: 0.612, green: 0.639, blue: 0.686)
  private let cBg = Color(red: 0.941, green: 0.945, blue: 0.957)

  var body: some View {
    ZStack {
      MovingGridLines(spacing: 32)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        // 打字机效果标题 + 闪烁光标
        HStack(spacing: 0) {
          Text(typedTitle)
            .font(ntFont(size: 36))
            .foregroundColor(cText)

          Rectangle()
            .fill(cText)
            .frame(width: 3, height: 44)
            .opacity(showCursor ? 1 : 0)
            .animation(
              .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
              value: showCursor
            )
        }
        .frame(height: 54)
        .padding(.top, 40)
        .onAppear { startTyping() }

        // 状态徽章
        HStack(spacing: 12) {
          StatusBadge(
            label: service.isEnabled ? "拦截已启用" : "拦截已停止",
            color: service.isEnabled ? .green : .orange
          )
          StatusBadge(
            label: service.isEnabled ? "后台守护运行中" : "后台守护已停止",
            color: service.isEnabled ? .green : .gray
          )
        }
        .padding(.top, 20)
        .padding(.bottom, 40)

        // 描述文字
        Text(
          service.isEnabled
            ? "Apple Music / iTunes 已被阻止启动\n点击按钮恢复"
            : "启用后将阻止 Apple Music / iTunes 启动\n不影响其他应用"
        )
        .font(ntFont(size: 13))
        .multilineTextAlignment(.center)
        .foregroundColor(cMuted)
        .lineSpacing(4)
        .padding(.bottom, 24)

        // 错误提示横幅
        if let error = errorMessage {
          HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.system(size: 12))
            Text(error)
              .font(ntFont(size: 12))
          }
          .foregroundColor(.orange)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(Color.orange.opacity(0.08))
          .cornerRadius(6)
          .padding(.bottom, 24)
          .transition(.opacity)
        }

        // 操作按钮
        VStack(spacing: 12) {
          Button {
            toggleAction()
          } label: {
            HStack(spacing: 10) {
              Image(systemName: service.isEnabled ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 18))
              Text(service.isEnabled ? "恢复音乐功能" : "禁用音乐")
                .font(ntFont(size: 18))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
              RoundedRectangle(cornerRadius: 12)
                .fill(service.isEnabled ? Color.green : Color.red)
                .shadow(
                  color: (service.isEnabled ? Color.green : Color.red).opacity(0.25),
                  radius: 8, x: 0, y: 4
                )
            )
          }
          .buttonStyle(PlainButtonStyle())
          .disabled(isLoading)

          if isLoading {
            ProgressView()
              .scaleEffect(0.8)
          }
        }
        .frame(width: 400)

        // 底部提示
        Text(
          service.isEnabled
            ? "已拦截 \(service.blockCount) 次"
            : "需要授予辅助功能权限"
        )
        .font(ntFont(size: 11))
        .foregroundColor(cMuted)
        .padding(.top, 16)

        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(cBg)
    .alert("操作失败", isPresented: $showError) {
      Button("确定", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "未知错误")
    }
    .onAppear {
      service.checkStatus()
      service.loadStats()
      if service.isEnabled {
        service.toggle(enabled: true)
      }
    }
    .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
      if service.isEnabled {
        service.loadStats()
      }
    }
  }

  // 逐字输出标题，完成后光标延迟消失
  private func startTyping() {
    showCursor = true
    var index = 0
    Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { timer in
      if index < fullTitle.count {
        let charIndex = fullTitle.index(fullTitle.startIndex, offsetBy: index)
        typedTitle.append(fullTitle[charIndex])
        index += 1
      } else {
        timer.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
          showCursor = false
        }
      }
    }
  }

  private func toggleAction() {
    let newValue = !service.isEnabled
    isLoading = true
    errorMessage = nil
    DispatchQueue.global(qos: .userInitiated).async {
      let success = service.toggle(enabled: newValue)
      DispatchQueue.main.async {
        isLoading = false
        service.checkStatus()
        if !success {
          errorMessage =
            newValue
            ? "无法创建或加载 Launch Agent，请检查磁盘权限"
            : "无法卸载 Launch Agent"
          showError = true
        }
      }
    }
  }
}

// 优先使用 JetBrains Mono，回退 Consolas，最后系统等宽字体
private func ntFont(size: CGFloat) -> Font {
  if let nsFont = NSFont(name: "JetBrains Mono", size: size) {
    return Font(nsFont as CTFont)
  }
  if let nsFont = NSFont(name: "Consolas", size: size) {
    return Font(nsFont as CTFont)
  }
  return Font.system(size: size, weight: .regular, design: .default)
}
