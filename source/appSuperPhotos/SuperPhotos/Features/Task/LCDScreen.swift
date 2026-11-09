import SwiftUI

/// 液晶屏规格：尺寸、字号、格子数、颜色集中在这里。
/// 设计稿到位后只改这组常量（以及 `LCDScreen` 里的文字样式），不改调用方。
enum LCDSpec {
    /// 屏幕总高（含外框与内边距）；中栏可用高度会因此减少这么多。
    static let height: CGFloat = 68
    /// 外框粗细：硬边占位边界。
    static let borderWidth: CGFloat = 1.5
    /// 屏内四周留白。
    static let innerPadding: CGFloat = 8
    /// 行与行之间的间距。
    static let lineSpacing: CGFloat = 4
    /// 进度条与文字之间额外加的距离。
    static let barTopSpacing: CGFloat = 2

    /// 屏内主文字：等宽 + 硬边，替代像素字体。
    static let textSize: CGFloat = 10.5
    static let textTracking: CGFloat = 0.4
    /// 手势提示行数上限。
    static let tipsLineLimit: Int = 3
    /// 角标文字。
    static let tagSize: CGFloat = 7
    static let tagTracking: CGFloat = 0.6

    /// 分段式进度条：格数、格间距、格高。
    static let segmentCount: Int = 24
    static let segmentSpacing: CGFloat = 2
    static let segmentHeight: CGFloat = 7

    /// 占位角标开关：设计稿到位后关掉即可。
    static let showsPlaceholderTag = true

    // 颜色
    static let screenFill = Theme.Surface.sunken
    static let borderColor = Theme.Shadow.insetBorder
    static let textColor = Theme.Text.primary
    static let dimColor = Theme.Text.tertiary
    static let emptySegmentColor = Theme.Text.tertiary.opacity(0.22)
    static let fillSegmentColor = Theme.Accent.brass
    static let dangerColor = Theme.State.danger
}

/// 液晶屏（占位版）：默认态（桌面）显示手势提示，处理态（舞台）显示进度。
///
/// 本轮只做占位——可见硬边外框 + 内部留白 + 「LCD · 占位」角标；
/// 处理态整屏仍是暂停入口，无障碍标签沿用原进度头的文案。
struct LCDScreen: View {
    enum Mode: Equatable {
        case tips
        case progress(pendingDelete: Int, processed: Int, total: Int)
    }

    let mode: Mode
    /// 处理态下整屏可点，作为暂停入口。
    var isPauseEnabled: Bool = false
    var onPause: () -> Void = {}

    /// 默认态手势提示：从桌面按钮下方移到这块屏里。
    static let tipsText = "轻点全屏 · 上滑延后 · 左滑保险箱 · 右滑收藏夹 · 下滑删除"

    var body: some View {
        Group {
            if isPauseEnabled, case .progress = mode {
                Button(action: onPause) {
                    screen
                }
                .buttonStyle(.plain)
                .accessibilityLabel("暂停整理")
                .accessibilityHint("保留当前进度并返回桌面")
                .accessibilityValue(accessibilitySummary)
            } else {
                screen
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilitySummary)
            }
        }
    }

    // MARK: - 屏体

    private var screen: some View {
        ZStack {
            LCDSpec.screenFill

            // 硬边外框：占位边界，后续换设计时整块替换。
            Rectangle()
                .strokeBorder(LCDSpec.borderColor, lineWidth: LCDSpec.borderWidth)

            VStack(alignment: .leading, spacing: LCDSpec.lineSpacing) {
                if LCDSpec.showsPlaceholderTag {
                    HStack(spacing: 0) {
                        Text("LCD")
                        Spacer(minLength: 4)
                        Text("占位 · 待设计稿")
                    }
                    .font(.system(size: LCDSpec.tagSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(LCDSpec.dimColor)
                    .tracking(LCDSpec.tagTracking)
                    .lineLimit(1)
                    .accessibilityHidden(true)
                }

                contentRow

                if case .progress = mode {
                    pixelBar
                        .padding(.top, LCDSpec.barTopSpacing)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(LCDSpec.innerPadding)
        }
        // 屏宽只由所在栏决定：内容（提示文案、进度数字）再长也不能把屏撑宽，
        // 否则中栏会被 LCD 的 ideal 宽度顶开，三栏落点一起漂。
        .frame(maxWidth: .infinity)
        .frame(height: LCDSpec.height)
        // 像素风：直角硬边，不做圆角与描边渐变。
        .clipShape(Rectangle())
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var contentRow: some View {
        switch mode {
        case .tips:
            Text(Self.tipsText)
                .font(.system(size: LCDSpec.textSize, weight: .medium, design: .monospaced))
                .foregroundStyle(LCDSpec.textColor)
                .tracking(LCDSpec.textTracking)
                .lineLimit(LCDSpec.tipsLineLimit)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)

        case let .progress(pendingDelete, processed, total):
            HStack(spacing: 6) {
                Text("待删除 \(pendingDelete) 张")
                    .foregroundStyle(pendingDelete > 0 ? LCDSpec.dangerColor : LCDSpec.dimColor)

                Spacer(minLength: 4)

                Text("\(processed)/\(total)")
                    .foregroundStyle(LCDSpec.textColor)
            }
            .font(.system(size: LCDSpec.textSize, weight: .medium, design: .monospaced).monospacedDigit())
            .tracking(LCDSpec.textTracking)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
    }

    // MARK: - 像素进度条

    private var pixelBar: some View {
        HStack(spacing: LCDSpec.segmentSpacing) {
            ForEach(0..<LCDSpec.segmentCount, id: \.self) { index in
                Rectangle()
                    .fill(index < filledSegments ? LCDSpec.fillSegmentColor : LCDSpec.emptySegmentColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: LCDSpec.segmentHeight)
            }
        }
        .frame(height: LCDSpec.segmentHeight)
        .animation(.easeOut(duration: 0.18), value: filledSegments)
        .accessibilityHidden(true)
    }

    /// 按比例点亮的格子数；分段式，只在满格时点亮最后一格。
    private var filledSegments: Int {
        guard case let .progress(_, processed, total) = mode, total > 0 else { return 0 }
        let ratio = Double(max(0, min(processed, total))) / Double(total)
        return min(LCDSpec.segmentCount, Int((ratio * Double(LCDSpec.segmentCount)).rounded()))
    }

    private var accessibilitySummary: String {
        switch mode {
        case .tips:
            return Self.tipsText
        case let .progress(pendingDelete, processed, total):
            return "待删除 \(pendingDelete) 张，已处理 \(processed) 张，共 \(total) 张"
        }
    }
}

#Preview("桌面 · 提示") {
    LCDScreen(mode: .tips)
        .padding()
        .background(Theme.Surface.base)
}

#Preview("舞台 · 进度") {
    LCDScreen(
        mode: .progress(pendingDelete: 3, processed: 37, total: 100),
        isPauseEnabled: true
    )
    .padding()
    .background(Theme.Surface.base)
}
