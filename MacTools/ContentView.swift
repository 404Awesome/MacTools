import SwiftUI

struct ContentView: View {
  #if DEBUG
    @ObserveInjection var forceRedraw
  #endif

  struct SidebarItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let view: () -> AnyView
    func hash(into hasher: inout Hasher) { hasher.combine(title) }
    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool { lhs.title == rhs.title }
  }
  let sidebarItems = [
    SidebarItem(title: "插件加载") { AnyView(PluginLoad()) },
    SidebarItem(title: "应用签名") { AnyView(AppSignature()) },
  ]

  @State private var selectedItem: SidebarItem?

  var body: some View {
    NavigationSplitView {
      List(sidebarItems, selection: $selectedItem) { item in
        NavigationLink(item.title, value: item)
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
    .enableInjection()
  }
}
