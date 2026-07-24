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
