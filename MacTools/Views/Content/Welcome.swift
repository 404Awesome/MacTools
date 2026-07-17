import SwiftUI

struct Welcome: View {
  #if DEBUG
  @ObserveInjection var forceRedraw
  #endif

  var body: some View {
    Text("Welcome View")
      .enableInjection()
  }
}
