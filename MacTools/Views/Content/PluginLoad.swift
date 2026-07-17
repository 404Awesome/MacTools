import SwiftUI

struct PluginLoad: View {
  #if DEBUG
  @ObserveInjection var forceRedraw
  #endif

  var body: some View {
    Text("PluginLoad View")
      .enableInjection()
  }
}
