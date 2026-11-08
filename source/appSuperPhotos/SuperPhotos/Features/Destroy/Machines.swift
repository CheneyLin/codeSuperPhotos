import SwiftUI

/// 壁炉炉膛：内凹深槽 + 暖光 + 火星。
struct FireplaceMouth: View {
    let phase: DestroyPhase
    let progress: Double

    private var isHot: Bool {
        phase == .charging || phase == .destroying
    }

    private var heat: Double {
        switch phase {
        case .charging: 0.45 + progress * 0.55
        case .destroying: 1
        case .armed: 0.35
        default: 0.18
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.165, green: 0.137, blue: 0.125),
                            Color(red: 0.09, green: 0.07, blue: 0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // 底部暖光
            RadialGradient(
                colors: [
                    Theme.Accent.fire.opacity(0.45 * heat),
                    Theme.Accent.ember.opacity(0.18 * heat),
                    .clear
                ],
                center: .bottom,
                startRadius: 2,
                endRadius: 120
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous))

            // 砖纹
            Canvas { context, size in
                var y: CGFloat = 10
                while y < size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(.white.opacity(0.035)), lineWidth: 1)
                    y += 13
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous))

            embers

            RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.black.opacity(0.55), .white.opacity(0.06), .black.opacity(0.45)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
        }
    }

    private var embers: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !isHot)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { graphics, size in
                for index in 0..<8 {
                    let seed = Double(index)
                    let cycle = 1.3 + (seed * 0.37).truncatingRemainder(dividingBy: 1) * 0.9
                    let raw = (t / cycle + seed * 0.41).truncatingRemainder(dividingBy: 1)
                    let life = raw
                    let x = size.width * (0.18 + 0.64 * (seed * 0.318).truncatingRemainder(dividingBy: 1))
                    let y = size.height * (0.95 - life * 0.85)
                    let radius = 1.2 + (1 - life) * 1.8
                    let alpha = (1 - life) * 0.85 * heat
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    graphics.fill(
                        Path(ellipseIn: rect),
                        with: .color(Theme.Accent.fire.opacity(max(0, alpha)))
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// 碎纸机刀口：金属外壳 + 深槽 + 滚轮 + 碎纸条下落。
struct ShredderMouth: View {
    let phase: DestroyPhase
    let progress: Double

    private var isRunning: Bool {
        phase == .charging || phase == .destroying
    }

    private var spinSpeed: Double {
        phase == .charging ? 90 + progress * 180 : (phase == .destroying ? 260 : 70)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.79, green: 0.81, blue: 0.84),
                            Color(red: 0.60, green: 0.64, blue: 0.68),
                            Color(red: 0.87, green: 0.89, blue: 0.91)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // 拉丝斜纹
            Canvas { context, size in
                var x: CGFloat = -size.height
                while x < size.width + size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    context.stroke(path, with: .color(.black.opacity(0.045)), lineWidth: 1)
                    x += 4
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous))

            // 滚轮条纹
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !isRunning)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Canvas { graphics, size in
                    let slotY = size.height * 0.42
                    let offset = (t * spinSpeed).truncatingRemainder(dividingBy: 12)
                    var x = -12 + offset
                    while x < size.width + 12 {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: slotY - 9))
                        path.addLine(to: CGPoint(x: x + 5, y: slotY - 2))
                        graphics.stroke(
                            path,
                            with: .color(.black.opacity(isRunning ? 0.22 : 0.1)),
                            lineWidth: 2
                        )
                        x += 12
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous))

            // 刀口
            Capsule()
                .fill(Color(red: 0.055, green: 0.063, blue: 0.07))
                .frame(height: 8)
                .overlay(alignment: .top) {
                    Capsule().fill(.white.opacity(0.35)).frame(height: 0.8)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(Theme.Accent.metal.opacity(0.15), lineWidth: 1)
                }
                .padding(.horizontal, Theme.Spacing.xl)

            if phase == .destroying {
                fallingStrips
            }
        }
    }

    /// 14 列碎纸条下落；替代真实切片，确认后才会出现。
    private var fallingStrips: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { graphics, size in
                let columns = 14
                let width = size.width / CGFloat(columns)
                for index in 0..<columns {
                    let seed = Double(index)
                    let delay = (seed * 0.137).truncatingRemainder(dividingBy: 0.12)
                    let elapsed = (t + seed * 0.91).truncatingRemainder(dividingBy: 1.4) - delay
                    guard elapsed > 0 else { continue }
                    let life = min(1, elapsed / 1.0)
                    let y = size.height * 0.46 + CGFloat(life) * size.height * 0.5
                    let stripHeight = size.height * 0.22
                    let rect = CGRect(
                        x: CGFloat(index) * width + 1,
                        y: y,
                        width: max(width - 2, 1),
                        height: stripHeight
                    )
                    let flicker = 0.5 + 0.35 * sin(seed + t * 9)
                    graphics.fill(
                        Path(roundedRect: rect, cornerRadius: 1),
                        with: .color(.white.opacity(max(0.06, flicker * (1 - life) * 0.55)))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview("机器") {
    VStack(spacing: Theme.Spacing.xl) {
        FireplaceMouth(phase: .idle, progress: 0)
            .frame(height: 88)
        FireplaceMouth(phase: .charging, progress: 0.6)
            .frame(height: 88)
        ShredderMouth(phase: .idle, progress: 0)
            .frame(height: 88)
        ShredderMouth(phase: .charging, progress: 0.8)
            .frame(height: 88)
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Surface.base)
}
