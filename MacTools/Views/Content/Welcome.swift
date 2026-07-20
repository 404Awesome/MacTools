import SwiftUI

// MARK: - 欢迎页(默认视图)
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
      // 网格背景铺满整个页面（带水平移动）
      MovingGridBackgroundView()
        .ignoresSafeArea()

      // 内容层居中
      VStack(spacing: 0) {
        // 打字机效果标题
        HStack(spacing: 0) {
          Text(typedText)
            .font(codeFont(size: 44))
            .foregroundColor(Color(red: 0.067, green: 0.067, blue: 0.153))

          // 闪烁光标
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

        // 副标题：从下往上渐入
        Text(tagline)
          .font(codeFont(size: 15))
          .foregroundColor(Color(red: 0.612, green: 0.639, blue: 0.686))
          .padding(.top, 18)
          .opacity(showContent ? 1 : 0)
          .offset(y: showContent ? 0 : 20)
          .animation(.easeOut(duration: 0.6).delay(0), value: showContent)

        // 按钮：从下往上渐入
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

// MARK: - 网格背景 + 浮动表情
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
      // 打乱表情池并截取所需数量，确保同一屏不重复
      let shuffledFaces = Array(faces.shuffled().prefix(positions.count))

      ZStack {
        // 水平移动的网格线（左上角对齐，铺满）
        MovingGridLines(spacing: gridSpacing)
          .frame(width: geo.size.width, height: geo.size.height)

        // 浮动表情（随机分布在四周，互不重叠）
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

  /// 随机生成不重叠的位置，避开中心文字区域
  private func generateNonOverlappingPositions(count: Int, size: CGSize, minDistance: CGFloat)
    -> [CGPoint]
  {
    // 防止尺寸为0或过小导致崩溃
    guard size.width > 100, size.height > 100 else {
      return []
    }

    // 中心文字区域（留空）
    let centerW: CGFloat = 340
    let centerH: CGFloat = 220
    let centerX = size.width / 2
    let centerY = size.height / 2
    let avoidMinX = centerX - centerW / 2
    let avoidMaxX = centerX + centerW / 2
    let avoidMinY = centerY - centerH / 2
    let avoidMaxY = centerY + centerH / 2

    var positions: [CGPoint] = []
    let margin: CGFloat = 50
    let maxAttempts = 500

    // 安全边界，确保 lowerBound <= upperBound
    let safeMinX = min(margin, size.width / 2)
    let safeMaxX = max(size.width - margin, size.width / 2 + 1)
    let safeMinY = min(margin, size.height / 2)
    let safeMaxY = max(size.height - margin, size.height / 2 + 1)

    for _ in 0..<count {
      var attempts = 0
      var found = false

      while attempts < maxAttempts && !found {
        let x = CGFloat.random(in: safeMinX...safeMaxX)
        let y = CGFloat.random(in: safeMinY...safeMaxY)
        let candidate = CGPoint(x: x, y: y)

        // 检查是否在中心区域
        let inCenter = x >= avoidMinX && x <= avoidMaxX && y >= avoidMinY && y <= avoidMaxY
        if inCenter {
          attempts += 1
          continue
        }

        // 检查是否与已有位置重叠
        var tooClose = false
        for existing in positions {
          let dx = candidate.x - existing.x
          let dy = candidate.y - existing.y
          let dist = sqrt(dx * dx + dy * dy)
          if dist < minDistance {
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

// MARK: - 水平移动的网格线（左上角对齐，铺满）
struct MovingGridLines: View {
  let spacing: CGFloat

  @State private var gridOffset: CGFloat = 0

  var body: some View {
    GeometryReader { geo in
      let hCount = Int(geo.size.width / spacing) + 4
      let vCount = Int(geo.size.height / spacing) + 4

      ZStack {
        // 竖线（从 x=0 开始，左上角对齐，水平移动）
        ForEach(0..<hCount, id: \.self) { i in
          Rectangle()
            .fill(Color.black.opacity(0.035))
            .frame(width: 1, height: geo.size.height)
            .position(x: 0, y: geo.size.height / 2)
            .offset(x: CGFloat(i) * spacing + gridOffset)
        }

        // 横线（从 y=0 开始，左上角对齐）
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

// MARK: - 浮动表情（不重叠，80%透明度）
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
