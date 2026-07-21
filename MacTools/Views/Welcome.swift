import SwiftUI

// 欢迎页：打字机标题、渐入内容与动态网格背景
struct Welcome: View {
  let onStart: () -> Void

  @State private var showContent = false
  @State private var isHovering = false
  @State private var typedText = ""
  @State private var showCursor = true
  let fullTitle = "MacTools"
  let tagline = "让每一次点击，都恰到好处"

  var body: some View {
    ZStack {
      MovingGridBackgroundView()
        .ignoresSafeArea()

      VStack(spacing: 0) {
        // 打字机效果标题 + 闪烁光标
        HStack(spacing: 0) {
          Text(typedText)
            .font(codeFont(size: 44))
            .foregroundColor(Color(red: 0.067, green: 0.067, blue: 0.153))

          Rectangle()
            .fill(Color(red: 0.067, green: 0.067, blue: 0.153))
            .frame(width: 3, height: 44)
            .opacity(showCursor ? 1 : 0)
            .animation(
              .easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: showCursor)
        }
        .frame(height: 54)
        .onAppear {
          startTyping()
        }

        // 副标题：从下方渐入
        Text(tagline)
          .font(codeFont(size: 15))
          .foregroundColor(Color(red: 0.612, green: 0.639, blue: 0.686))
          .padding(.top, 18)
          .opacity(showContent ? 1 : 0)
          .offset(y: showContent ? 0 : 20)
          .animation(.easeOut(duration: 0.6), value: showContent)

        // 开始按钮：从下方渐入，支持悬停缩放
        Button(action: onStart) {
          HStack(spacing: 8) {
            Text("开始使用")
              .font(codeFont(size: 14))
            Image(systemName: "chevron.right")
              .font(.system(size: 12, weight: .semibold))
          }
          .foregroundColor(.white)
          .padding(.horizontal, 32)
          .padding(.vertical, 12)
          .background(Color(red: 0.067, green: 0.067, blue: 0.153))
          .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.top, 40)
        .opacity(showContent ? 1 : 0)
        .offset(y: showContent ? 0 : 20)
        .animation(.easeOut(duration: 0.6).delay(0.15), value: showContent)
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .onHover { hovering in
          withAnimation(.easeInOut(duration: 0.2)) {
            isHovering = hovering
          }
        }
      }
      .zIndex(10)
    }
    .background(Color(red: 0.941, green: 0.945, blue: 0.957))
  }

  // 逐字打印标题，完成后触发内容显示并隐藏光标
  private func startTyping() {
    showCursor = true
    var index = 0
    Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { timer in
      if index < fullTitle.count {
        let charIndex = fullTitle.index(fullTitle.startIndex, offsetBy: index)
        typedText.append(fullTitle[charIndex])
        index += 1
      } else {
        timer.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          withAnimation(.easeOut(duration: 0.5)) {
            showContent = true
          }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
          showCursor = false
        }
      }
    }
  }

  // 优先使用 JetBrains Mono，回退到 Consolas，最后使用系统字体
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

// 动态背景：水平移动的网格线 + 随机分布的浮动表情
struct MovingGridBackgroundView: View {
  let faces: [String] = [
    "😂", "🤣", "🥹", "😉", "😘", "😋", "🤨", "🤓", "😎", "🤩", "🥳", "😏", "😭", "😠", "🤫", "🤔", "🫩", "🤤", "🤡",
    "🥴",
  ]
  let gridSpacing: CGFloat = 32
  let faceCount = 18

  var body: some View {
    GeometryReader { geo in
      let positions = generateNonOverlappingPositions(
        count: faceCount,
        size: geo.size,
        minDistance: 70
      )
      let shuffledFaces = Array(faces.shuffled().prefix(positions.count))

      ZStack {
        MovingGridLines(spacing: gridSpacing)

        ForEach(0..<positions.count, id: \.self) { i in
          let pos = positions[i]
          FloatingFace(
            emoji: shuffledFaces[i],
            size: CGFloat(48 + Int.random(in: 0...24)),
            baseX: pos.x,
            baseY: pos.y,
            animIndex: i % 4,
            delay: Double(i) * 0.3
          )
        }
      }
    }
  }

  // 在视图边缘随机生成互不重叠的位置，避开中心文字区域
  private func generateNonOverlappingPositions(count: Int, size: CGSize, minDistance: CGFloat)
    -> [CGPoint]
  {
    guard size.width > 100, size.height > 100 else { return [] }

    let centerX = size.width / 2
    let centerY = size.height / 2
    let avoidMinX = centerX - 170
    let avoidMaxX = centerX + 170
    let avoidMinY = centerY - 110
    let avoidMaxY = centerY + 110

    var positions: [CGPoint] = []
    let margin: CGFloat = 50
    let maxAttempts = 500

    for _ in 0..<count {
      var attempts = 0
      var found = false

      while attempts < maxAttempts && !found {
        let x = CGFloat.random(in: margin...size.width - margin)
        let y = CGFloat.random(in: margin...size.height - margin)
        let candidate = CGPoint(x: x, y: y)

        if x >= avoidMinX && x <= avoidMaxX && y >= avoidMinY && y <= avoidMaxY {
          attempts += 1
          continue
        }

        var tooClose = false
        for existing in positions {
          let dx = candidate.x - existing.x
          let dy = candidate.y - existing.y
          if sqrt(dx * dx + dy * dy) < minDistance {
            tooClose = true
            break
          }
        }

        if !tooClose {
          positions.append(candidate)
          found = true
        }

        attempts += 1
      }
    }

    return positions
  }
}

// 水平无限循环移动的网格线
struct MovingGridLines: View {
  let spacing: CGFloat

  @State private var gridOffset: CGFloat = 0

  var body: some View {
    GeometryReader { geo in
      let hCount = Int(geo.size.width / spacing) + 4
      let vCount = Int(geo.size.height / spacing) + 4

      ZStack {
        // 竖线：从左向右排列，整体水平平移实现循环滚动
        ForEach(0..<hCount, id: \.self) { i in
          Rectangle()
            .fill(Color.black.opacity(0.035))
            .frame(width: 1, height: geo.size.height)
            .position(x: 0, y: geo.size.height / 2)
            .offset(x: CGFloat(i) * spacing + gridOffset)
        }

        // 横线：从上向下排列
        ForEach(0..<vCount, id: \.self) { i in
          Rectangle()
            .fill(Color.black.opacity(0.035))
            .frame(width: geo.size.width, height: 1)
            .position(x: geo.size.width / 2, y: 0)
            .offset(y: CGFloat(i) * spacing)
        }
      }
      .onAppear {
        withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
          gridOffset = -spacing
        }
      }
    }
  }
}

// 浮动表情：根据 animIndex 应用不同方向的漂移动画
struct FloatingFace: View {
  let emoji: String
  let size: CGFloat
  let baseX: CGFloat
  let baseY: CGFloat
  let animIndex: Int
  let delay: Double

  @State private var offsetY: CGFloat = 0
  @State private var offsetX: CGFloat = 0

  var body: some View {
    Text(emoji)
      .font(.system(size: size))
      .opacity(0.8)
      .position(x: baseX, y: baseY)
      .offset(x: offsetX, y: offsetY)
      .onAppear {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
          switch animIndex {
          case 0:
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
              offsetY = -10
            }
          case 1:
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
              offsetY = 10
            }
          case 2:
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
              offsetX = -8
            }
          case 3:
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
              offsetX = 8
            }
          default:
            break
          }
        }
      }
  }
}
