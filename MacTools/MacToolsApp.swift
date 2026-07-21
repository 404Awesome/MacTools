import SwiftUI

@main
struct MacToolsApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .commands {
      SidebarCommands()
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 900, height: 570)
  }
}

// 内联热重载兼容性代码：当项目未引入 HotSwiftUI 或 Inject 包时，
// 提供 DEBUG 模式下 InjectionIII / InjectionNext 所需的最小基础设施。
#if canImport(HotSwiftUI)
  @_exported import HotSwiftUI
#elseif canImport(Inject)
  @_exported import Inject
#else

  #if DEBUG
    import Combine

    // 监听 Injection 通知的单例，通过发布状态变更触发视图重绘。
    public class InjectionObserver: ObservableObject {
      public static let shared = InjectionObserver()
      @Published var injectionNumber = 0
      var cancellable: AnyCancellable?
      let publisher = PassthroughSubject<Void, Never>()

      init() {
        cancellable = NotificationCenter.default.publisher(
          for: Notification.Name("INJECTION_BUNDLE_NOTIFICATION")
        )
        .sink { [weak self] _ in
          self?.injectionNumber += 1
          self?.publisher.send()
        }
      }
    }

    extension SwiftUI.View {
      // 类型擦除包装，用于消除热重载后的类型差异。
      public func eraseToAnyView() -> some SwiftUI.View {
        AnyView(self)
      }

      // 启用热重载支持，DEBUG 下执行类型擦除。
      public func enableInjection() -> some SwiftUI.View {
        eraseToAnyView()
      }

      // 接收 Injection 通知后执行自定义状态刷新逻辑。
      public func onInjection(bumpState: @escaping () -> Void) -> some SwiftUI.View {
        self
          .onReceive(InjectionObserver.shared.publisher, perform: bumpState)
          .eraseToAnyView()
      }
    }

    // 属性包装器：观察 InjectionObserver 的变化以强制视图重绘。
    @propertyWrapper
    public struct ObserveInjection: DynamicProperty {
      @ObservedObject private var iO = InjectionObserver.shared
      public init() {}
      public private(set) var wrappedValue: Int {
        get { 0 }
        set {}
      }
    }
  #else
    // RELEASE 模式：热重载 API 退化为空实现，编译后无运行时开销。
    extension SwiftUI.View {
      @inline(__always)
      public func eraseToAnyView() -> some SwiftUI.View { self }

      @inline(__always)
      public func enableInjection() -> some SwiftUI.View { self }

      @inline(__always)
      public func onInjection(bumpState: @escaping () -> Void) -> some SwiftUI.View {
        self
      }
    }

    @propertyWrapper
    public struct ObserveInjection {
      public init() {}
      public private(set) var wrappedValue: Int {
        get { 0 }
        set {}
      }
    }
  #endif
#endif
