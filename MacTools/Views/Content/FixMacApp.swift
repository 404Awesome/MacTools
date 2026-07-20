import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 修复应用主视图（Welcome 风格 · 纯网格背景）
struct FixMacApp: View {
  @State private var selectedApp: URL?
  @State private var hasQuarantine: Bool = false
  @State private var isProcessing: Bool = false
  @State private var statusMessage: String = ""
  @State private var statusColor: Color = Color(red: 0.612, green: 0.639, blue: 0.686)

  // 打字机效果
  @State private var typedTitle = ""
  @State private var showCursor = true
  private let fullTitle = "修复应用"

  // 系统状态
  @State private var sipEnabled: Bool = true
  @State private var anySourceEnabled: Bool = false

  // 拖放悬停
  @State private var isDropHovering: Bool = false

  // 颜色常量
  private let cText = Color(red: 0.067, green: 0.067, blue: 0.153)
  private let cMuted = Color(red: 0.612, green: 0.639, blue: 0.686)
  private let cBg = Color(red: 0.941, green: 0.945, blue: 0.957)

  var body: some View {
    ZStack {
      // 复用 Welcome.swift 中已定义的 MovingGridLines
      MovingGridLines(spacing: 32)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        // 顶部标题区（打字机效果）
        HStack(spacing: 0) {
          Text(typedTitle)
            .font(codeFont(size: 36))
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
        .onAppear {
          startTyping()
        }

        // 系统状态标签
        HStack(spacing: 12) {
          StatusBadge(
            label: sipEnabled ? "SIP 已开启" : "SIP 已关闭",
            color: sipEnabled ? .green : .orange
          )
          StatusBadge(
            label: anySourceEnabled ? "任何来源" : "App Store + 认证",
            color: anySourceEnabled ? .green : .blue
          )
        }
        .padding(.top, 20)
        .padding(.bottom, 32)

        // 拖放区域
        DropZoneView(onDrop: handleDrop, isHovering: $isDropHovering)
          .frame(width: 400, height: 140)
          .background(
            RoundedRectangle(cornerRadius: 12)
              .fill(Color.white)
              .overlay(
                RoundedRectangle(cornerRadius: 12)
                  .stroke(
                    isDropHovering
                      ? cText.opacity(0.25)
                      : cText.opacity(0.12),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
                  )
              )
              .animation(.easeInOut(duration: 0.2), value: isDropHovering)
          )
          .overlay(
            VStack(spacing: 6) {
              Image(systemName: isDropHovering ? "arrow.down.circle.fill" : "app.dashed")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(
                  isDropHovering
                    ? cText.opacity(0.35)
                    : cText.opacity(0.18)
                )
                .animation(.easeInOut(duration: 0.2), value: isDropHovering)

              Text("拖入应用到这里")
                .font(codeFont(size: 13))
                .foregroundColor(cMuted)

              Text("或点击选择")
                .font(codeFont(size: 11))
                .foregroundColor(cMuted.opacity(0.7))
            }
          )
          .padding(.bottom, 32)

        // 应用信息
        if let app = selectedApp {
          appInfoCard(app: app)
            .padding(.bottom, 20)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        // 状态消息
        if !statusMessage.isEmpty {
          HStack(spacing: 6) {
            Image(systemName: statusIcon)
              .font(.system(size: 12))
            Text(statusMessage)
              .font(codeFont(size: 12))
          }
          .foregroundColor(statusColor)
          .padding(.horizontal, 14)
          .padding(.vertical, 6)
          .background(statusColor.opacity(0.08))
          .cornerRadius(6)
          .padding(.bottom, 16)
          .transition(.opacity)
        }

        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(cBg)
    .onAppear {
      checkSystemStatus()
    }
  }

  private var statusIcon: String {
    switch statusColor {
    case .green: return "checkmark.circle.fill"
    case .red: return "xmark.circle.fill"
    case .orange: return "exclamationmark.triangle.fill"
    default: return "info.circle.fill"
    }
  }

  // MARK: - 打字机效果
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

  // MARK: - 检测系统状态
  private func checkSystemStatus() {
    DispatchQueue.global(qos: .userInitiated).async {
      let sipOutput = runCommand("/usr/bin/csrutil", ["status"])
      let sipOn = sipOutput.contains("enabled")

      let spctlOutput = runCommand("/usr/sbin/spctl", ["--status"])
      let assessmentsDisabled = spctlOutput.contains("disabled")

      DispatchQueue.main.async {
        sipEnabled = sipOn
        anySourceEnabled = assessmentsDisabled
      }
    }
  }

  // MARK: - 应用信息卡片
  @ViewBuilder
  private func appInfoCard(app: URL) -> some View {
    VStack(spacing: 20) {
      HStack(spacing: 12) {
        AppIconView(url: app)
          .id(app.path)

        VStack(alignment: .leading, spacing: 2) {
          Text(app.lastPathComponent)
            .font(codeFont(size: 14))
            .foregroundColor(cText)
            .lineLimit(1)
        }

        Spacer()

        HStack(spacing: 5) {
          Circle()
            .fill(hasQuarantine ? Color.orange : Color.green)
            .frame(width: 6, height: 6)
          Text(hasQuarantine ? "已隔离" : "正常")
            .font(codeFont(size: 11))
            .foregroundColor(hasQuarantine ? .orange : .green)
        }
      }
      .padding(.horizontal, 16)

      HStack(spacing: 10) {
        Button(action: checkQuarantine) {
          HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 11))
            Text(isProcessing ? "检查中..." : "检查属性")
              .font(codeFont(size: 12))
          }
          .foregroundColor(cText)
          .padding(.horizontal, 16)
          .padding(.vertical, 7)
          .background(cText.opacity(0.06))
          .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isProcessing)

        if hasQuarantine {
          Button(action: removeQuarantine) {
            HStack(spacing: 5) {
              Image(systemName: "lock.open")
                .font(.system(size: 11))
              Text(isProcessing ? "移除中..." : "移除隔离")
                .font(codeFont(size: 12))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(cText)
            .cornerRadius(6)
          }
          .buttonStyle(PlainButtonStyle())
          .disabled(isProcessing)
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 16)
    }
    .padding(.top, 16)
    .frame(width: 400)
    .background(Color.white)
    .cornerRadius(12)
    .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
  }

  // MARK: - 处理拖放
  private func handleDrop(_ url: URL) {
    withAnimation(.easeOut(duration: 0.3)) {
      selectedApp = url
      hasQuarantine = false
      statusMessage = ""
    }

    DispatchQueue.global(qos: .userInitiated).async {
      let result = runCommand("/usr/bin/xattr", ["-l", url.path])
      let hasAttr = result.contains("com.apple.quarantine")

      DispatchQueue.main.async {
        withAnimation(.easeOut(duration: 0.3)) {
          hasQuarantine = hasAttr
          statusMessage = hasAttr ? "检测到隔离属性" : "未检测到隔离属性"
          statusColor = hasAttr ? .orange : .green
        }
      }
    }
  }

  // MARK: - 检查隔离属性
  private func checkQuarantine() {
    guard let app = selectedApp else { return }
    isProcessing = true
    statusMessage = ""

    DispatchQueue.global(qos: .userInitiated).async {
      let result = runCommand("/usr/bin/xattr", ["-l", app.path])
      let hasAttr = result.contains("com.apple.quarantine")

      DispatchQueue.main.async {
        withAnimation(.easeOut(duration: 0.3)) {
          hasQuarantine = hasAttr
          isProcessing = false
          statusMessage = hasAttr ? "检测到隔离属性" : "未检测到隔离属性"
          statusColor = hasAttr ? .orange : .green
        }
      }
    }
  }

  // MARK: - 移除隔离属性
  private func removeQuarantine() {
    guard let app = selectedApp else { return }
    isProcessing = true
    statusMessage = ""

    DispatchQueue.global(qos: .userInitiated).async {
      let output = runCommand("/usr/bin/xattr", ["-d", "com.apple.quarantine", app.path])
      let success = output.isEmpty || output.contains("No such xattr")

      DispatchQueue.main.async {
        withAnimation(.easeOut(duration: 0.3)) {
          isProcessing = false
          if success {
            hasQuarantine = false
            statusMessage = "成功移除隔离属性"
            statusColor = .green
          } else {
            statusMessage = "移除失败: \(output)"
            statusColor = .red
          }
        }
      }
    }
  }

  private func codeFont(size: CGFloat) -> Font {
    if let nsFont = NSFont(name: "JetBrains Mono", size: size) {
      return Font(nsFont as CTFont)
    }
    if let nsFont = NSFont(name: "Consolas", size: size) {
      return Font(nsFont as CTFont)
    }
    return Font.system(size: size, weight: .regular, design: .default)
  }
}

// MARK: - 状态标签
struct StatusBadge: View {
  let label: String
  let color: Color

  var body: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(color)
        .frame(width: 6, height: 6)
      Text(label)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(color)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(color.opacity(0.08))
    .cornerRadius(6)
  }
}

// MARK: - 应用图标视图
struct AppIconView: View {
  let url: URL
  @State private var icon: NSImage?

  var body: some View {
    Group {
      if let icon = icon {
        Image(nsImage: icon)
          .resizable()
          .aspectRatio(contentMode: .fit)
      } else {
        Image(systemName: "app.fill")
          .font(.system(size: 28))
          .foregroundColor(Color(red: 0.067, green: 0.067, blue: 0.153).opacity(0.3))
      }
    }
    .frame(width: 36, height: 36)
    .onAppear {
      loadIcon()
    }
  }

  private func loadIcon() {
    icon = NSWorkspace.shared.icon(forFile: url.path)
  }
}

// MARK: - 拖放区域视图
struct DropZoneView: NSViewRepresentable {
  let onDrop: (URL) -> Void
  @Binding var isHovering: Bool

  func makeNSView(context: Context) -> NSView {
    let view = DropZoneNSView()
    view.onDrop = onDrop
    view.onHoverChanged = { hovering in
      DispatchQueue.main.async {
        isHovering = hovering
      }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - 拖放区域 NSView
class DropZoneNSView: NSView {
  var onDrop: ((URL) -> Void)?
  var onHoverChanged: ((Bool) -> Void)?
  private var isDragging = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setup()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setup()
  }

  private func setup() {
    registerForDraggedTypes([.fileURL])
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.cornerRadius = 12
  }

  override func mouseDown(with event: NSEvent) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = [UTType.application, UTType.package]

    if panel.runModal() == .OK, let url = panel.url {
      onDrop?(url)
    }
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    isDragging = true
    onHoverChanged?(true)
    return .copy
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    isDragging = false
    onHoverChanged?(false)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    isDragging = false
    onHoverChanged?(false)

    guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil),
      let url = items.first as? URL
    else {
      return false
    }
    onDrop?(url)
    return true
  }
}

// MARK: - 命令执行
func runCommand(_ path: String, _ args: [String]) -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: path)
  process.arguments = args

  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = pipe

  do {
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? ""
  } catch {
    return error.localizedDescription
  }
}
