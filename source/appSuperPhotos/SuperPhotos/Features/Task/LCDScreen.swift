import SwiftUI

/// 液晶屏规格：物料图、玻璃屏在图片里的位置，以及屏内读数的排版常量。
///
/// 物料是 720×421 的透明 PNG；屏体尺寸、圆角、挂耳全部在图片里，
/// 代码不再画边框、圆角或占位角标。
enum LCDSpec {
    /// 读数排版基准宽：旧版 1:1 屏宽 162（486px ÷ 3）。
    /// 屏内字号 / 字距 / 条高都按「实际屏宽 ÷ 162」等比放大。
    static let baseWidth: CGFloat = 162
    /// 目标宽 240：顶部整行改成「左按钮区 / LCD / 右按钮区」三段后，
    /// 393 宽屏上还剩 153pt 给两侧，各约 68pt，正好放得下 64pt 的圆形操作按钮。
    /// 300 宽时两侧只剩 46.5pt，放不下按钮，所以收到 240。
    static let displayWidth: CGFloat = 260
    /// 左右按钮区的最小宽度：与 `PegboardHookButton`（圆形图标按钮）的 64pt 命中框一致。
    /// 两侧区等宽弹性分配，LCD 因此始终精确居中。
    static let sideButtonWidth: CGFloat = 64
    /// 顶部整行的左右外边距。8pt 时 393 宽屏按钮中心落在约 42pt，
    /// 与旧版挂件的 43pt 基本同轴。
    static let headerPadding: CGFloat = 8
    /// 物料原始「高 / 宽」比例（720 × 421 → 0.5847），只用来由宽度反推高度。
    ///
    /// 注意方向：SwiftUI 的 `aspectRatio(_:contentMode:)` 参数是「宽 / 高」。
    /// 曾把本值直接传进去，屏体被约束成 0.5847 的竖向比例，300pt 宽只剩约 102pt，
    /// 且玻璃区、读数一起跟着变形。渲染统一改用 `.scaledToFit()` 读图片自身比例，
    /// 常量只服务于布局计算，不再参与图片约束。
    static let imageAspect: CGFloat = 421.0 / 720.0
    /// 物料在目标宽下的渲染高度（240 × 0.5847 ≈ 140.3）。
    static var displayHeight: CGFloat { displayWidth * imageAspect }

    /// 顶部整行的固定占位高度：沿用 150，屏体 140.3pt 贴在行顶，
    /// 底部约 9.7pt 透明留白隔开三栏行。整行进 `safeAreaInset`，
    /// 三栏行不再单独扣这一行，切换桌面 / 处理态时行高完全不跳。
    static let rowHeight: CGFloat = 150

    /// 物料上下透明留白的比例（可见区 y 31…377，总高 421）。
    /// 定位按「可见边框」算、命中区也裁掉留白：放大的屏体可以吃掉挂板区空白，
    /// 但透明像素既不会压到顶栏挂件，也不会挡住提示条或三栏行的点击。
    static let visibleTopRatio: CGFloat = 31.0 / 421.0
    static let visibleBottomRatio: CGFloat = 44.0 / 421.0

    /// 玻璃屏在图片中的归一化矩形（按 486×284 实测：x 48.5…439、y 94.5…210.5）。
    /// 文字与进度条只落在这个矩形内，压在外框、挂耳或透明留白上都不会出现。
    static let glassRect = CGRect(x: 0.0998, y: 0.3327, width: 0.8035, height: 0.4085)
    /// 读数与玻璃边缘的留白，按玻璃宽/高的比例给，随图片缩放自动等比例变化。
    /// 10% 是实测下限：再小文字会贴到玻璃圆角与边框上。
    static let glassInsetRatio: CGFloat = 0.10

    /// 屏内主读数：等宽 + 硬边，替代像素字体。
    static let textSize: CGFloat = 10
    static let textTracking: CGFloat = 0.2
    /// 主读数 / 进度条 / 底部提示三行之间的距离。
    /// 屏宽 300 时玻璃可用高约 57pt，1.5 是容纳三行且不贴边的上限。
    static let lineSpacing: CGFloat = 1.5

    /// 底部提示行（常驻提示与瞬时反馈共用这一格）：比主读数小一档。
    static let hintSize: CGFloat = 7
    static let hintTracking: CGFloat = 0.1
    /// 处理态没有瞬时反馈时的常驻提示。
    static let hintText = "轻点暂停 · 下滑待销毁"

    /// 分段式进度条：格数、格间距、格高（同样按屏体缩放）。
    static let segmentCount: Int = 16
    static let segmentSpacing: CGFloat = 2
    static let segmentHeight: CGFloat = 6

    // 颜色
    /// 屏内文字用主题前景色：浅色模式下压浅蓝屏、深色模式下压暗蓝屏都保持高对比。
    static let textColor = Theme.Text.primary
    static let dimColor = Theme.Text.tertiary
    static let emptySegmentColor = Theme.Text.primary.opacity(0.14)
    static let fillSegmentColor = Theme.Text.primary
    static let dangerColor = Theme.State.danger
}

/// 屏内瞬时反馈。同一时刻只保留一条：后来的直接覆盖前面的，不排队。
struct LCDNotice: Identifiable, Equatable {
    enum Tone: Equatable {
        case info
        case success
        /// 只有“加入待销毁”用红色，其余统一用屏内墨色。
        case danger
    }

    let id = UUID()
    let text: String
    var tone: Tone = .info
}

/// 液晶屏的可见矩形：扣掉物料上下透明留白，只让屏面本身接收点击。
private struct VisibleScreenShape: Shape {
    let topRatio: CGFloat
    let bottomRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let top = rect.height * topRatio
        let bottom = rect.height * bottomRatio
        return Path(
            CGRect(
                x: rect.minX,
                y: rect.minY + top,
                width: rect.width,
                height: max(0, rect.height - top - bottom)
            )
        )
    }
}

/// 液晶屏：图片驱动，按「桌面 / 处理中」与深浅主题切换四张物料。
///
/// - 桌面态：屏面不渲染进度，也不显示手势提示；只有瞬时反馈时露出一行。
/// - 处理中：玻璃屏内三行——主读数、分段进度条、底部提示（瞬时反馈优先）。
///   整屏仍是暂停入口。
struct LCDScreen: View {
    enum Mode: Equatable {
        case idle
        case progress(pendingDelete: Int, processed: Int, total: Int)
    }

    let mode: Mode
    /// 最新的操作反馈；2.4s 后由调用方清空。
    var notice: LCDNotice?
    /// 处理态下整屏可点，作为暂停入口。
    var isPauseEnabled: Bool = false
    var onPause: () -> Void = {}

    /// 桌面态手势提示：不画在屏上，只留给 VoiceOver。
    static let tipsText = "轻点全屏 · 上滑延后 · 左滑保险箱 · 右滑收藏夹 · 下滑删除"

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if isPauseEnabled, isProgress {
                Button(action: onPause) {
                    panel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("暂停整理")
                .accessibilityHint("保留当前进度并返回桌面")
                .accessibilityValue(accessibilitySummary)
            } else {
                panel
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilitySummary)
            }
        }
    }

    private var isProgress: Bool {
        if case .progress = mode { return true }
        return false
    }

    /// 物料映射：`-on` 两张实测是「屏面点亮、画面退淡」的版本，正好当读数底图。
    private var assetName: String {
        switch (isProgress, colorScheme) {
        case (true, .dark):
            return "lcd_progress_dark"
        case (true, _):
            return "lcd_progress_light"
        case (false, .dark):
            return "lcd_idle_dark"
        case (false, _):
            return "lcd_idle_light"
        }
    }

    // MARK: - 屏体

    private var panel: some View {
        Image(assetName)
            .resizable()
            // 等比完整显示：直接取图片自身的宽高比（720:421），不拉伸、不裁切。
            // 外框与挂耳都是图片的一部分；不要用 aspectRatio(LCDSpec.imageAspect)，
            // 那个常量是「高/宽」，传进去会把屏体压成竖条。
            .scaledToFit()
            // 命中区只覆盖可见屏面：上下透明留白不接收点击，放大的屏体不会
            // 借透明像素挡住顶栏、提示条或三栏行。
            .contentShape(VisibleScreenShape(
                topRatio: LCDSpec.visibleTopRatio,
                bottomRatio: LCDSpec.visibleBottomRatio
            ))
            .overlay {
                if isProgress || notice != nil {
                    GeometryReader { proxy in
                        let glass = glassRect(in: proxy.size)
                        // 读数跟随屏体等比缩放：屏越大字越大，不会在小图上溢出、在大图上留白。
                        let scale = proxy.size.width / LCDSpec.baseWidth
                        readout(scale: scale)
                            .frame(
                                width: glass.width * (1 - 2 * LCDSpec.glassInsetRatio),
                                height: glass.height * (1 - 2 * LCDSpec.glassInsetRatio)
                            )
                            .position(x: glass.midX, y: glass.midY)
                    }
                }
            }
    }

    /// 图片实际渲染尺寸下，玻璃屏对应的矩形。
    private func glassRect(in size: CGSize) -> CGRect {
        CGRect(
            x: size.width * LCDSpec.glassRect.minX,
            y: size.height * LCDSpec.glassRect.minY,
            width: size.width * LCDSpec.glassRect.width,
            height: size.height * LCDSpec.glassRect.height
        )
    }

    // MARK: - 屏内读数

    @ViewBuilder
    private func readout(scale: CGFloat) -> some View {
        switch mode {
        case .idle:
            // 桌面态：手势提示不显示，这里只有瞬时反馈，居中一行。
            if notice != nil {
                statusLine(scale: scale, isHint: false, alignment: .center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        case let .progress(pendingDelete, processed, total):
            VStack(alignment: .leading, spacing: LCDSpec.lineSpacing * scale) {
                HStack(spacing: 4 * scale) {
                    Text("待删除 \(pendingDelete) 张")
                        .foregroundStyle(pendingDelete > 0 ? LCDSpec.dangerColor : LCDSpec.dimColor)

                    Spacer(minLength: 2 * scale)

                    Text("\(processed)/\(total)")
                        .foregroundStyle(LCDSpec.textColor)
                }
                .font(.system(size: LCDSpec.textSize * scale, weight: .semibold, design: .monospaced).monospacedDigit())
                .tracking(LCDSpec.textTracking * scale)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                pixelBar(scale: scale)

                // 瞬时反馈占用底部这一格；没有反馈时回落为常驻提示。
                statusLine(scale: scale, isHint: notice == nil)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    /// 底部提示行：常驻手势提示与瞬时反馈共用同一格，互不顶位。
    private func statusLine(
        scale: CGFloat,
        isHint: Bool,
        alignment: Alignment = .leading
    ) -> some View {
        let text = isHint ? LCDSpec.hintText : (notice?.text ?? "")
        return Text(text)
            .font(.system(size: LCDSpec.hintSize * scale, weight: .semibold, design: .monospaced))
            .tracking(LCDSpec.hintTracking * scale)
            .foregroundStyle(isHint ? LCDSpec.dimColor : noticeColor)
            .lineLimit(1)
            // 先整体收缩，缩到 65% 还放不下才截断加省略号。
            .minimumScaleFactor(0.65)
            .truncationMode(.tail)
            .multilineTextAlignment(alignment == .center ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: alignment)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.18), value: text)
    }

    private var noticeColor: Color {
        notice?.tone == .danger ? LCDSpec.dangerColor : LCDSpec.textColor
    }

    private func pixelBar(scale: CGFloat) -> some View {
        let height = LCDSpec.segmentHeight * scale
        return HStack(spacing: LCDSpec.segmentSpacing * scale) {
            ForEach(0..<LCDSpec.segmentCount, id: \.self) { index in
                Rectangle()
                    .fill(index < filledSegments ? LCDSpec.fillSegmentColor : LCDSpec.emptySegmentColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
        }
        .frame(height: height)
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
        let base: String
        switch mode {
        case .idle:
            base = Self.tipsText
        case let .progress(pendingDelete, processed, total):
            base = "待删除 \(pendingDelete) 张，已处理 \(processed) 张，共 \(total) 张"
        }
        guard let notice else { return base }
        return "\(base)。\(notice.text)"
    }
}

private extension LCDScreen {
    /// 预览与调用方共用的尺寸：宽度由调用方给，高度按物料比例算。
    func sized(width: CGFloat) -> some View {
        frame(width: width, height: width * LCDSpec.imageAspect)
    }
}

#Preview("桌面 · 浅色") {
    LCDScreen(mode: .idle)
        .sized(width: LCDSpec.displayWidth)
        .padding()
        .background(Theme.Surface.base)
        .preferredColorScheme(.light)
}

#Preview("桌面 · 深色") {
    LCDScreen(mode: .idle)
        .sized(width: LCDSpec.displayWidth)
        .padding()
        .background(Theme.Surface.base)
        .preferredColorScheme(.dark)
}

#Preview("舞台 · 进度") {
    LCDScreen(
        mode: .progress(pendingDelete: 3, processed: 37, total: 100),
        isPauseEnabled: true
    )
    .sized(width: LCDSpec.displayWidth)
    .padding()
    .background(Theme.Surface.base)
}

#Preview("舞台 · 瞬时反馈") {
    LCDScreen(
        mode: .progress(pendingDelete: 3, processed: 37, total: 100),
        notice: LCDNotice(text: "已加入「旅行」", tone: .success),
        isPauseEnabled: true
    )
    .sized(width: LCDSpec.displayWidth)
    .padding()
    .background(Theme.Surface.base)
}
