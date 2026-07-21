import SwiftUI

struct ContentView: View {
  #if DEBUG
    @ObserveInjection var forceRedraw
  #endif

  struct SidebarItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let view: () -> AnyView

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool { lhs.id == rhs.id }
  }

  let sidebarItems = [
    SidebarItem(title: "插件加载") { AnyView(PluginLoad()) },
    SidebarItem(title: "修复应用") { AnyView(FixMacApp()) },
    SidebarItem(title: "环境信息") { AnyView(EnvInfo()) },
  ]

  @State private var selectedItem: SidebarItem?
  @State private var columnVisibility: NavigationSplitViewVisibility = .all

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      List(sidebarItems, selection: $selectedItem) { item in
        Text(item.title)
          .tag(item)
      }
    } detail: {
      if let item = selectedItem {
        item.view()
      } else {
        Welcome {
          selectedItem = sidebarItems[0]
        }
      }
    }
    .background(
      ShortcutMonitor(key: "s", modifiers: .command) {
        withAnimation(.easeInOut(duration: 0.2)) {
          columnVisibility = (columnVisibility == .all) ? .detailOnly : .all
        }
      }
    )
    .navigationTitle("MacTools")
    .enableInjection()
  }
}

struct ShortcutMonitor: NSViewRepresentable {
  let key: String
  let modifiers: NSEvent.ModifierFlags
  let action: () -> Void

  func makeNSView(context: Context) -> NSView {
    let view = ShortcutHostingView()
    view.key = key.lowercased()
    view.modifiers = modifiers
    view.action = action
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    guard let view = nsView as? ShortcutHostingView else { return }
    view.key = key.lowercased()
    view.modifiers = modifiers
    view.action = action
  }

  class ShortcutHostingView: NSView {
    var key: String = ""
    var modifiers: NSEvent.ModifierFlags = []
    var action: (() -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window != nil {
        registerMonitor()
      } else {
        unregisterMonitor()
      }
    }

    private func registerMonitor() {
      guard monitor == nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self = self else { return event }
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let mod = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if chars == self.key && mod == self.modifiers {
          self.action?()
          return nil
        }
        return event
      }
    }

    private func unregisterMonitor() {
      if let monitor = monitor {
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
      }
    }

    deinit {
      unregisterMonitor()
    }
  }
}
