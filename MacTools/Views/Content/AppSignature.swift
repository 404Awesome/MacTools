import SwiftUI

struct AppSignature: View {
  #if DEBUG
    @ObserveInjection var forceRedraw
  #endif

  var body: some View {
    Text("AppSignature View")
      .enableInjection()
  }
}
