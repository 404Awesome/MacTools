import AppKit
import Combine
import CoreGraphics
import SwiftUI

// NX_SYSDEFINED 对应系统定义事件，用于捕获亮度、音量等媒体键/功能键
private let NX_SYSDEFINED: UInt32 = 14
private let NX_SUBTYPE_AUX_CONTROL_BUTTONS: Int64 = 8

// CGEventTap 回调：返回 nil 则丢弃事件，返回事件对象则放行到系统
private func keyboardEventCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  if type.rawValue == NX_SYSDEFINED {
    let subtype = event.getIntegerValueField(.eventSourceUserData)
    if subtype == NX_SUBTYPE_AUX_CONTROL_BUTTONS {
      return nil
    }
    return Unmanaged.passRetained(event)
  }
  return nil
}

// 管理键盘拦截器的生命周期、辅助功能权限检测及状态发布
class KeyboardManager: ObservableObject {
  @Published var isKeyboardDisabled = false
  @Published var permissionGranted = false
  @Published var errorMessage: String?

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

  init() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appWillTerminate),
      name: NSApplication.willTerminateNotification,
      object: nil
    )
    checkPermission()
  }

  // 静默检测当前进程是否已被授予辅助功能权限
  func checkPermission() {
    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
    permissionGranted = AXIsProcessTrustedWithOptions(options as CFDictionary)
    if permissionGranted {
      errorMessage = nil
    }
  }

  func toggleKeyboard() {
    isKeyboardDisabled ? enableKeyboard() : disableKeyboard()
  }

  // 创建事件拦截器：覆盖普通按键、修饰键变化及系统定义事件（功能键/媒体键）
  private func disableKeyboard() {
    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]

    guard AXIsProcessTrustedWithOptions(options as CFDictionary) else {
      permissionGranted = false
      errorMessage = "需要辅助功能权限才能禁用键盘。\n请在系统设置 > 隐私与安全性 > 辅助功能 中授权。"
      return
    }

    permissionGranted = true
    errorMessage = nil

    let eventMask =
      (1 << CGEventType.keyDown.rawValue)
      | (1 << CGEventType.keyUp.rawValue)
      | (1 << CGEventType.flagsChanged.rawValue)
      | (1 << NX_SYSDEFINED)

    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(eventMask),
        callback: keyboardEventCallback,
        userInfo: nil
      )
    else {
      errorMessage = "无法创建键盘事件拦截器，请检查权限设置。"
      return
    }

    eventTap = tap
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    withAnimation(.spring(response: 0.35)) {
      isKeyboardDisabled = true
    }
  }

  // 关闭事件拦截器并从 RunLoop 中移除，恢复键盘响应
  private func enableKeyboard() {
    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
    }
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }
    eventTap = nil
    runLoopSource = nil

    withAnimation(.spring(response: 0.35)) {
      isKeyboardDisabled = false
    }
  }

  // 应用终止前强制恢复键盘，防止键盘永久失效
  @objc private func appWillTerminate() {
    enableKeyboard()
  }

  deinit {
    enableKeyboard()
    NotificationCenter.default.removeObserver(self)
  }
}

struct DisableKeyboard: View {
  @StateObject private var keyboardManager = KeyboardManager()

  @State private var typedTitle = ""
  @State private var showCursor = true
  private let fullTitle = "禁用键盘"

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
        .onAppear { startTyping() }

        // 权限状态与键盘拦截状态徽章
        HStack(spacing: 12) {
          StatusBadge(
            label: keyboardManager.permissionGranted ? "辅助功能已授权" : "辅助功能未授权",
            color: keyboardManager.permissionGranted ? .green : .orange
          )
          StatusBadge(
            label: keyboardManager.isKeyboardDisabled ? "键盘已拦截" : "键盘运行中",
            color: keyboardManager.isKeyboardDisabled ? .red : .green
          )
        }
        .padding(.top, 20)
        .padding(.bottom, 40)

        // 根据当前状态显示对应的操作提示
        Text(
          keyboardManager.isKeyboardDisabled
            ? "现在可以安全地清洁键盘了\n鼠标和触控板仍可正常使用"
            : "清洁键盘前，点击下方按钮禁用内置键盘\n防止误触输入"
        )
        .font(codeFont(size: 13))
        .multilineTextAlignment(.center)
        .foregroundColor(cMuted)
        .lineSpacing(4)
        .padding(.bottom, 24)

        // 错误提示横幅
        if let error = keyboardManager.errorMessage {
          HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.system(size: 12))
            Text(error)
              .font(codeFont(size: 12))
          }
          .foregroundColor(.orange)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(Color.orange.opacity(0.08))
          .cornerRadius(6)
          .padding(.bottom, 24)
          .transition(.opacity)
        }

        // 操作按钮组：未授权时显示设置入口，主按钮控制拦截开关
        VStack(spacing: 12) {
          if !keyboardManager.permissionGranted {
            Button {
              if let url = URL(
                string:
                  "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
              {
                NSWorkspace.shared.open(url)
              }
            } label: {
              HStack(spacing: 10) {
                Image(systemName: "gear")
                  .font(.system(size: 18))
                Text("打开辅助功能设置")
                  .font(codeFont(size: 18))
              }
              .foregroundColor(cText)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
              .background(
                RoundedRectangle(cornerRadius: 12)
                  .fill(Color.white)
                  .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
              )
            }
            .buttonStyle(PlainButtonStyle())
          }

          Button {
            keyboardManager.toggleKeyboard()
          } label: {
            HStack(spacing: 10) {
              Image(systemName: keyboardManager.isKeyboardDisabled ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 18))
              Text(keyboardManager.isKeyboardDisabled ? "恢复键盘功能" : "禁用键盘")
                .font(codeFont(size: 18))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
              RoundedRectangle(cornerRadius: 12)
                .fill(keyboardManager.isKeyboardDisabled ? Color.green : Color.red)
                .shadow(
                  color: (keyboardManager.isKeyboardDisabled ? Color.green : Color.red).opacity(
                    0.25), radius: 8, x: 0, y: 4)
            )
          }
          .buttonStyle(PlainButtonStyle())
        }
        .frame(width: 400)

        // 底部辅助提示
        Text(
          keyboardManager.isKeyboardDisabled
            ? "退出软件后键盘会自动恢复"
            : "需要授予辅助功能权限"
        )
        .font(codeFont(size: 11))
        .foregroundColor(cMuted)
        .padding(.top, 16)

        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(cBg)
    .onAppear {
      keyboardManager.checkPermission()
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

  // 等宽字体回退：JetBrains Mono → Consolas → 系统默认
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
