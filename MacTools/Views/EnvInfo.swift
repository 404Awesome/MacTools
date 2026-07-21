import Foundation
import SwiftUI

// 同步执行 Shell 命令并返回标准输出
nonisolated func runShell(_ launchPath: String, args: [String]) -> String? {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: launchPath)
  process.arguments = args

  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = pipe

  do {
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)
  } catch {
    return nil
  }
}

// 在后台隔离任务中执行 Shell 命令，避免阻塞主线程
nonisolated func runShellAsync(_ launchPath: String, args: [String]) async -> String? {
  await Task.detached {
    runShell(launchPath, args: args)
  }.value
}

// 解析 brew list --versions 的文本输出，映射为 name: version
nonisolated func parseBrewVersions(_ output: String) -> [String: String] {
  var map: [String: String] = [:]
  for line in output.components(separatedBy: CharacterSet.newlines) {
    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
    guard let name = parts.first else { continue }
    let version = parts.count > 1 ? String(parts[1]) : "-"
    map[String(name)] = version
  }
  return map
}

// 截断版本号字符串，仅保留主版本号（如 v1.2.3）
nonisolated func truncateVersion(_ version: String) -> String {
  let pattern = #"^(v?\d+\.\d+\.\d+)"#
  guard let regex = try? NSRegularExpression(pattern: pattern),
    let match = regex.firstMatch(in: version, range: NSRange(version.startIndex..., in: version)),
    let range = Range(match.range(at: 1), in: version)
  else {
    return version
  }
  return String(version[range])
}

// 环境版本卡片数据
struct EnvVersion: Identifiable {
  let id = UUID()
  let name: String
  let version: String
  let icon: String
  let color: Color
}

// 通用包条目（NPM）
struct PackageItem: Identifiable {
  let id = UUID()
  let name: String
  let version: String?
}

// Homebrew 条目
struct BrewItem: Identifiable {
  let id = UUID()
  let name: String
  let version: String
}

// 全局搜索结果临时结构
struct SearchResult: Identifiable {
  let id = UUID()
  let name: String
  let version: String?
  let source: String
}

// 环境信息主视图：展示 Node/NPM/Homebrew 版本及已安装包列表
struct EnvInfo: View {
  @State private var envVersions: [EnvVersion] = []

  @State private var npmPackages: [PackageItem] = []
  @State private var npmError: String?
  @State private var isLoadingNPM = true

  @State private var brewManual: [BrewItem] = []
  @State private var brewDeps: [BrewItem] = []
  @State private var brewCasks: [BrewItem] = []
  @State private var brewError: String?
  @State private var isLoadingBrew = true

  @State private var selectedTab = 0
  @State private var searchText = ""

  private let cardColumns = [GridItem(.adaptive(minimum: 180), spacing: 12)]
  private let pkgColumns = [GridItem(.adaptive(minimum: 220), spacing: 8)]

  private var filteredNPMPackages: [PackageItem] {
    filterPackages(npmPackages, by: searchText)
  }

  private var filteredBrewManual: [BrewItem] {
    filterBrewItems(brewManual, by: searchText)
  }

  private var filteredBrewDeps: [BrewItem] {
    filterBrewItems(brewDeps, by: searchText)
  }

  private var filteredBrewCasks: [BrewItem] {
    filterBrewItems(brewCasks, by: searchText)
  }

  var body: some View {
    GeometryReader { geo in
      ZStack {
        MovingGridLines(spacing: 32)
          .ignoresSafeArea()
        NoScrollerScrollView {
          VStack(spacing: 24) {
            versionCardsSection
            packagesSection
          }
          .padding(28)
          .frame(width: max(0, geo.size.width - 16), alignment: .topLeading)
        }
      }
      .background(Color(red: 0.941, green: 0.945, blue: 0.957))
    }
    .navigationTitle("EnvInfo")
    .task {
      await loadAllAsync()
    }
  }

  private func filterPackages(_ packages: [PackageItem], by text: String) -> [PackageItem] {
    guard !text.isEmpty else { return packages }
    return packages.filter {
      $0.name.localizedCaseInsensitiveContains(text)
    }
  }

  private func filterBrewItems(_ items: [BrewItem], by text: String) -> [BrewItem] {
    guard !text.isEmpty else { return items }
    return items.filter {
      $0.name.localizedCaseInsensitiveContains(text)
    }
  }

  private var versionCardsSection: some View {
    LazyVGrid(columns: cardColumns, spacing: 12) {
      ForEach(envVersions) { env in
        VersionCard(env: env)
      }
    }
  }

  private var packagesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeader(title: "已安装工具", icon: "cube.box")

      HStack(spacing: 12) {
        SearchField(text: $searchText)
          .frame(maxWidth: 240)
          .frame(height: 26)

        Spacer()

        if searchText.isEmpty {
          Picker("", selection: $selectedTab) {
            Text("NPM (\(npmPackages.count))").tag(0)
            Text("Brew手动 (\(brewManual.count))").tag(1)
            Text("Brew依赖 (\(brewDeps.count))").tag(2)
            Text("BrewCask (\(brewCasks.count))").tag(3)
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 400)
          .frame(height: 26)
        }
      }

      Group {
        if searchText.isEmpty {
          switch selectedTab {
          case 0: npmListView
          case 1: brewManualListView
          case 2: brewDepsListView
          case 3: brewCaskListView
          default: EmptyView()
          }
        } else {
          globalSearchResultsView
        }
      }
      .transaction { $0.animation = nil }
    }
  }

  private var globalSearchResultsView: some View {
    Group {
      if filteredNPMPackages.isEmpty && filteredBrewManual.isEmpty && filteredBrewDeps.isEmpty
        && filteredBrewCasks.isEmpty
      {
        NoMatchPlaceholder(query: searchText)
      } else {
        VStack(alignment: .leading, spacing: 20) {
          if !filteredNPMPackages.isEmpty {
            searchGroup(
              title: "NPM 全局",
              items: filteredNPMPackages.map {
                SearchResult(name: $0.name, version: $0.version, source: "NPM")
              })
          }
          if !filteredBrewManual.isEmpty {
            searchGroup(
              title: "Brew 手动",
              items: filteredBrewManual.map {
                SearchResult(name: $0.name, version: $0.version, source: "Brew 手动")
              })
          }
          if !filteredBrewDeps.isEmpty {
            searchGroup(
              title: "Brew 依赖",
              items: filteredBrewDeps.map {
                SearchResult(name: $0.name, version: $0.version, source: "Brew 依赖")
              })
          }
          if !filteredBrewCasks.isEmpty {
            searchGroup(
              title: "Brew Cask",
              items: filteredBrewCasks.map {
                SearchResult(name: $0.name, version: $0.version, source: "Brew Cask")
              })
          }
        }
      }
    }
  }

  private func searchGroup(title: String, items: [SearchResult]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(codeFont(size: 13))
        .foregroundStyle(Color(red: 0.612, green: 0.639, blue: 0.686))
        .padding(.leading, 4)

      LazyVGrid(columns: pkgColumns, spacing: 8) {
        ForEach(items) { item in
          PackageCell(name: item.name, version: item.version, source: item.source)
        }
      }
    }
  }

  private var npmListView: some View {
    Group {
      if isLoadingNPM {
        LoadingPlaceholder(message: "正在扫描 NPM 全局包...")
      } else if let npmError {
        ErrorPlaceholder(message: npmError, icon: "exclamationmark.triangle")
      } else if npmPackages.isEmpty {
        EmptyPlaceholder(message: "未检测到全局 NPM 包", icon: "shippingbox")
      } else {
        LazyVGrid(columns: pkgColumns, spacing: 8) {
          ForEach(npmPackages) { pkg in
            PackageCell(name: pkg.name, version: pkg.version, source: nil)
          }
        }
      }
    }
  }

  private var brewManualListView: some View {
    Group {
      if isLoadingBrew {
        LoadingPlaceholder(message: "正在扫描 Homebrew...")
      } else if let brewError {
        ErrorPlaceholder(message: brewError, icon: "exclamationmark.triangle")
      } else if brewManual.isEmpty {
        EmptyPlaceholder(message: "未检测到手动安装的 Formula", icon: "mug")
      } else {
        LazyVGrid(columns: pkgColumns, spacing: 8) {
          ForEach(brewManual) { pkg in
            PackageCell(name: pkg.name, version: pkg.version, source: nil)
          }
        }
      }
    }
  }

  private var brewDepsListView: some View {
    Group {
      if isLoadingBrew {
        LoadingPlaceholder(message: "正在扫描 Homebrew...")
      } else if let brewError {
        ErrorPlaceholder(message: brewError, icon: "exclamationmark.triangle")
      } else if brewDeps.isEmpty {
        EmptyPlaceholder(message: "未检测到依赖 Formula", icon: "arrow.down.circle")
      } else {
        LazyVGrid(columns: pkgColumns, spacing: 8) {
          ForEach(brewDeps) { pkg in
            PackageCell(name: pkg.name, version: pkg.version, source: nil)
          }
        }
      }
    }
  }

  private var brewCaskListView: some View {
    Group {
      if isLoadingBrew {
        LoadingPlaceholder(message: "正在扫描 Homebrew...")
      } else if let brewError {
        ErrorPlaceholder(message: brewError, icon: "exclamationmark.triangle")
      } else if brewCasks.isEmpty {
        EmptyPlaceholder(message: "未检测到 Cask", icon: "app")
      } else {
        LazyVGrid(columns: pkgColumns, spacing: 8) {
          ForEach(brewCasks) { pkg in
            PackageCell(name: pkg.name, version: pkg.version, source: nil)
          }
        }
      }
    }
  }

  // 并发加载所有环境数据
  private func loadAllAsync() async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        let versions = await loadEnvVersions()
        await MainActor.run { self.envVersions = versions }
      }
      group.addTask {
        let result = await loadNPMPackages()
        await MainActor.run {
          self.npmPackages = result.packages
          self.npmError = result.error
          self.isLoadingNPM = false
        }
      }
      group.addTask {
        let result = await loadBrewPackages()
        await MainActor.run {
          self.brewManual = result.manual
          self.brewDeps = result.deps
          self.brewCasks = result.casks
          self.brewError = result.error
          self.isLoadingBrew = false
        }
      }
    }
  }

  // 获取 Node.js、NPM、Homebrew 的版本号
  private func loadEnvVersions() async -> [EnvVersion] {
    async let nodeTask = runShellAsync("/bin/zsh", args: ["-l", "-c", "node -v 2>/dev/null"])
    async let npmTask = runShellAsync("/bin/zsh", args: ["-l", "-c", "npm -v 2>/dev/null"])
    async let brewTask = runShellAsync(
      "/bin/zsh", args: ["-l", "-c", "brew --version 2>/dev/null | head -n 1 | awk '{print $2}'"])

    var versions: [EnvVersion] = []

    if let nodeV = await nodeTask?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
      !nodeV.isEmpty
    {
      versions.append(.init(name: "Node.js", version: nodeV, icon: "n.circle.fill", color: .green))
    } else {
      versions.append(.init(name: "Node.js", version: "未安装", icon: "n.circle.fill", color: .gray))
    }

    if let npmV = await npmTask?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
      !npmV.isEmpty
    {
      versions.append(
        .init(name: "NPM", version: "v\(npmV)", icon: "shippingbox.fill", color: .red))
    } else {
      versions.append(.init(name: "NPM", version: "未安装", icon: "shippingbox.fill", color: .gray))
    }

    if let brewV = await brewTask?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
      !brewV.isEmpty
    {
      let shortVersion = truncateVersion(brewV)
      versions.append(
        .init(name: "Homebrew", version: "v\(shortVersion)", icon: "mug.fill", color: .orange))
    } else {
      versions.append(.init(name: "Homebrew", version: "未安装", icon: "mug.fill", color: .gray))
    }

    return versions
  }

  // 获取 NPM 全局包列表，支持 JSON、目录遍历、文本解析三种降级策略
  private func loadNPMPackages() async -> (packages: [PackageItem], error: String?) {
    if let jsonOutput = await runShellAsync(
      "/bin/zsh", args: ["-l", "-c", "npm list -g --depth=0 --json 2>/dev/null"]),
      let data = jsonOutput.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let deps = json["dependencies"] as? [String: [String: Any]]
    {

      var packages: [PackageItem] = []
      for (name, info) in deps.sorted(by: { $0.key < $1.key }) {
        let version = info["version"] as? String
        packages.append(.init(name: name, version: version))
      }
      return (packages, nil)
    }

    if let globalPath = await runShellAsync(
      "/bin/zsh", args: ["-l", "-c", "npm root -g 2>/dev/null"])?.trimmingCharacters(
        in: CharacterSet.whitespacesAndNewlines),
      !globalPath.isEmpty
    {
      let fm = FileManager.default
      var packages: [PackageItem] = []

      if let contents = try? fm.contentsOfDirectory(atPath: globalPath) {
        for item in contents.sorted() {
          if item.hasPrefix(".") || item == ".bin" || item == ".modules.yaml" { continue }
          let pkgJsonPath = (globalPath as NSString).appendingPathComponent("\(item)/package.json")
          var version: String?
          if let data = fm.contents(atPath: pkgJsonPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
          {
            version = json["version"] as? String
          }
          packages.append(.init(name: item, version: version))
        }
      }
      if !packages.isEmpty { return (packages, nil) }
    }

    if let output = await runShellAsync(
      "/bin/zsh", args: ["-l", "-c", "npm list -g --depth=0 2>/dev/null"])
    {
      let lines = output.components(separatedBy: CharacterSet.newlines)
      var packages: [PackageItem] = []
      for line in lines {
        let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
        let prefixes = ["├── ", "└── ", "├─ ", "└─ ", "├──", "└──", "├─", "└─"]
        for prefix in prefixes {
          if trimmed.hasPrefix(prefix) {
            let raw = trimmed.replacingOccurrences(of: prefix, with: "")
            let parts = raw.split(separator: "@", maxSplits: 1).map(String.init)
            let name = parts.first?.trimmingCharacters(in: CharacterSet.whitespaces) ?? raw
            let version =
              parts.count > 1 ? parts[1].trimmingCharacters(in: CharacterSet.whitespaces) : nil
            packages.append(.init(name: name, version: version))
            break
          }
        }
      }
      if !packages.isEmpty { return (packages, nil) }
    }

    let hasNPM =
      await runShellAsync("/bin/zsh", args: ["-l", "-c", "which npm 2>/dev/null"]) != nil
    return ([], hasNPM ? "未检测到全局 NPM 包" : "未检测到 NPM，请确认已安装 Node.js")
  }

  // 获取 Homebrew 手动安装、依赖及 Cask 列表
  private func loadBrewPackages() async -> (
    manual: [BrewItem], deps: [BrewItem], casks: [BrewItem], error: String?
  ) {
    let hasBrew =
      await runShellAsync("/bin/zsh", args: ["-l", "-c", "which brew 2>/dev/null"]) != nil
    guard hasBrew else {
      return ([], [], [], "未检测到 Homebrew，请确认已安装")
    }

    async let leavesTask = runShellAsync("/bin/zsh", args: ["-l", "-c", "brew leaves 2>/dev/null"])
    async let formulaVersionsTask = runShellAsync(
      "/bin/zsh", args: ["-l", "-c", "brew list --versions --formula 2>/dev/null"])
    async let caskVersionsTask = runShellAsync(
      "/bin/zsh", args: ["-l", "-c", "brew list --versions --cask 2>/dev/null"])

    let leavesOutput = await leavesTask ?? ""
    let formulaVersionsOutput = await formulaVersionsTask ?? ""
    let caskVersionsOutput = await caskVersionsTask ?? ""

    let leavesSet = Set(
      leavesOutput.components(separatedBy: CharacterSet.newlines).map {
        $0.trimmingCharacters(in: CharacterSet.whitespaces)
      }.filter { !$0.isEmpty })
    let formulaMap = parseBrewVersions(formulaVersionsOutput)
    let caskMap = parseBrewVersions(caskVersionsOutput)

    var manual: [BrewItem] = []
    var deps: [BrewItem] = []

    for (name, version) in formulaMap.sorted(by: { $0.key < $1.key }) {
      let shortVersion = truncateVersion(version)
      if leavesSet.contains(name) {
        manual.append(.init(name: name, version: shortVersion))
      } else {
        deps.append(.init(name: name, version: shortVersion))
      }
    }

    let casks = caskMap.sorted(by: { $0.key < $1.key }).map {
      BrewItem(name: $0.key, version: truncateVersion($0.value))
    }

    let errorMsg: String? =
      (manual.isEmpty && deps.isEmpty && casks.isEmpty) ? "未检测到 Homebrew 包" : nil
    return (manual, deps, casks, errorMsg)
  }
}

// 搜索框
struct SearchField: View {
  @Binding var text: String

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 13))
        .foregroundStyle(Color(red: 0.612, green: 0.639, blue: 0.686))

      TextField("搜索包名...", text: $text)
        .font(codeFont(size: 13))
        .textFieldStyle(.plain)

      if !text.isEmpty {
        Button(action: { text = "" }) {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 13))
            .foregroundStyle(Color(red: 0.612, green: 0.639, blue: 0.686))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 26)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.white.opacity(0.7))
        .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 1)
    )
  }
}

// 环境版本卡片
struct VersionCard: View {
  let env: EnvVersion

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: env.icon)
        .font(.system(size: 22))
        .foregroundStyle(env.color)
        .frame(width: 36, height: 36)
        .background(env.color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))

      VStack(alignment: .leading, spacing: 2) {
        Text(env.name)
          .font(codeFont(size: 11))
          .foregroundStyle(Color(red: 0.612, green: 0.639, blue: 0.686))
        Text(env.version)
          .font(codeFont(size: 15))
          .foregroundStyle(Color(red: 0.067, green: 0.067, blue: 0.153))
      }

      Spacer()
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color.white.opacity(0.85))
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
    )
  }
}

// 分区标题
struct SectionHeader: View {
  let title: String
  let icon: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 14))
        .foregroundStyle(Color(red: 0.067, green: 0.067, blue: 0.153).opacity(0.7))
      Text(title)
        .font(codeFont(size: 17))
        .foregroundStyle(Color(red: 0.067, green: 0.067, blue: 0.153))
      Spacer()
    }
  }
}

// 包条目单元格
struct PackageCell: View {
  let name: String
  let version: String?
  let source: String?

  var body: some View {
    HStack(spacing: 6) {
      Text(name)
        .font(codeFont(size: 14))
        .foregroundStyle(Color(red: 0.067, green: 0.067, blue: 0.153))
        .lineLimit(1)

      Spacer(minLength: 4)

      if let version {
        Text(version)
          .font(codeFont(size: 13))
          .foregroundStyle(Color(red: 0.612, green: 0.639, blue: 0.686))
      }

      if let source {
        Text(source)
          .font(codeFont(size: 10))
          .foregroundStyle(Color(red: 0.612, green: 0.639, blue: 0.686))
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(Color(red: 0.612, green: 0.639, blue: 0.686).opacity(0.10))
          .clipShape(RoundedRectangle(cornerRadius: 4))
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.6))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}

// 加载中占位
struct LoadingPlaceholder: View {
  let message: String

  var body: some View {
    HStack(spacing: 8) {
      ProgressView()
        .scaleEffect(0.8)
      Text(message)
        .font(codeFont(size: 14))
        .foregroundStyle(Color(red: 0.612, green: 0.639, blue: 0.686))
    }
    .frame(maxWidth: .infinity, minHeight: 80)
    .background(Color.white.opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}

// 错误占位
struct ErrorPlaceholder: View {
  let message: String
  let icon: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .foregroundStyle(.orange)
      Text(message)
        .font(codeFont(size: 14))
        .foregroundStyle(Color(red: 0.612, green: 0.639, blue: 0.686))
    }
    .frame(maxWidth: .infinity, minHeight: 80)
    .background(Color.orange.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}

// 空状态占位
struct EmptyPlaceholder: View {
  let message: String
  let icon: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .foregroundStyle(Color(red: 0.612, green: 0.639, blue: 0.686))
      Text(message)
        .font(codeFont(size: 14))
        .foregroundStyle(Color(red: 0.612, green: 0.639, blue: 0.686))
    }
    .frame(maxWidth: .infinity, minHeight: 80)
    .background(Color.white.opacity(0.4))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}

// 搜索无结果占位
struct NoMatchPlaceholder: View {
  let query: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(Color(red: 0.612, green: 0.639, blue: 0.686))
      Text("无匹配结果：\"\(query)\"")
        .font(codeFont(size: 14))
        .foregroundStyle(Color(red: 0.612, green: 0.639, blue: 0.686))
    }
    .frame(maxWidth: .infinity, minHeight: 80)
    .background(Color.white.opacity(0.4))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}

// 优先使用 JetBrains Mono，回退 Consolas，最后系统等宽字体
private func codeFont(size: CGFloat) -> Font {
  if let nsFont = NSFont(name: "JetBrains Mono", size: size) {
    return Font(nsFont as CTFont)
  }
  if let nsFont = NSFont(name: "Consolas", size: size) {
    return Font(nsFont as CTFont)
  }
  return Font.system(size: size, design: .monospaced)
}

// 自定义无滚动条 NSScrollView，解决 SwiftUI ScrollView 在 LazyVGrid 动态高度下的跳动问题
struct NoScrollerScrollView<Content: View>: NSViewRepresentable {
  @ViewBuilder let content: Content

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = false
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.verticalScrollElasticity = .none

    let hostingView = NSHostingView(rootView: content)
    hostingView.autoresizingMask = []

    let documentView = DocumentView()
    documentView.hostingView = hostingView
    documentView.addSubview(hostingView)
    scrollView.documentView = documentView
    context.coordinator.hostingView = hostingView
    context.coordinator.documentView = documentView

    return scrollView
  }

  func updateNSView(_ nsView: NSScrollView, context: Context) {
    NSAnimationContext.beginGrouping()
    NSAnimationContext.current.duration = 0

    nsView.contentView.scroll(to: NSPoint(x: 0, y: 0))
    context.coordinator.hostingView?.rootView = content
    context.coordinator.documentView?.needsLayout = true
    context.coordinator.documentView?.layoutSubtreeIfNeeded()

    NSAnimationContext.endGrouping()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  class Coordinator {
    var hostingView: NSHostingView<Content>?
    var documentView: DocumentView?
  }

  class DocumentView: NSView {
    var hostingView: NSHostingView<Content>?

    override var isFlipped: Bool { true }

    override func layout() {
      super.layout()
      guard let hostingView = hostingView, let clipView = superview as? NSClipView else { return }
      let width = clipView.bounds.width
      guard width > 0 else { return }

      NSAnimationContext.beginGrouping()
      NSAnimationContext.current.duration = 0
      CATransaction.begin()
      CATransaction.setDisableActions(true)

      let clipHeight = clipView.bounds.height
      let tempHeight: CGFloat = 20000

      hostingView.frame = NSRect(x: 0, y: 0, width: width, height: tempHeight)
      hostingView.needsLayout = true
      hostingView.layoutSubtreeIfNeeded()

      var contentHeight = hostingView.fittingSize.height

      if contentHeight.isInfinite || contentHeight.isNaN || contentHeight <= 0 {
        contentHeight = clipHeight
      }
      if contentHeight > tempHeight {
        contentHeight = tempHeight
      }

      let docHeight = max(contentHeight, clipHeight)

      self.frame = NSRect(x: 0, y: 0, width: width, height: docHeight)
      hostingView.frame = NSRect(x: 0, y: 0, width: width, height: contentHeight)

      CATransaction.commit()
      NSAnimationContext.endGrouping()
    }
  }
}
