import SwiftUI

/// 背景成品图的几何比例：所有落点都按同一份比例计算，
/// 保证内容与图中的桌面、洞洞板对齐。
/// 原图 1088×2368，以下比例以图高/图宽为基准。
enum SceneryLayout {
    static let imageWidth: CGFloat = 1088
    static let imageHeight: CGFloat = 2368

    /// 洞洞板上沿（相对图高）
    static let pegTopRatio: CGFloat = 0.097
    /// 桌面上沿：内容落桌的基准线
    static let benchTopRatio: CGFloat = 0.828
    /// 桌面前沿（桌板下沿）：只用于约束裁切，保证桌面完整可见
    static let benchFrontRatio: CGFloat = 0.854

    struct Metrics {
        /// aspectFill 后的绘制尺寸
        var scaledSize: CGSize
        /// 图片左上角在容器中的位置（负值表示被裁到容器外）
        var origin: CGPoint
        /// 桌面上沿在容器坐标中的落点
        var benchTopY: CGFloat
    }

    /// 适配策略：等比 aspectFill，不拉伸；横向居中裁切，纵向优先保底（桌面）。
    /// 顶部裁切量取折中：
    /// 1) 尽量不裁掉洞洞板（上留 10pt）；
    /// 2) 但桌面下沿必须留在容器内（下留 10pt），桌面优先于洞洞板。
    static func metrics(in size: CGSize) -> Metrics {
        guard size.width > 0, size.height > 0 else {
            return Metrics(scaledSize: .zero, origin: .zero, benchTopY: size.height)
        }

        let scale = max(size.width / imageWidth, size.height / imageHeight)
        let scaledW = imageWidth * scale
        let scaledH = imageHeight * scale
        let overflowX = max(0, scaledW - size.width)
        let overflowY = max(0, scaledH - size.height)

        let pegBound = max(0, pegTopRatio * scaledH - 10)
        let benchBound = max(0, benchFrontRatio * scaledH - (size.height - 10))
        let cropY = min(overflowY, max(pegBound, benchBound))
        let origin = CGPoint(x: -overflowX / 2, y: -cropY)

        return Metrics(
            scaledSize: CGSize(width: scaledW, height: scaledH),
            origin: origin,
            benchTopY: origin.y + benchTopRatio * scaledH
        )
    }
}

/// 主界面的实体桌面外壳：墙面 + 洞洞板 + 木桌的成品位图。
/// 纯装饰层，不参与命中测试，也不承载任何业务状态。
struct SceneryBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    var body: some View {
        GeometryReader { proxy in
            let metrics = SceneryLayout.metrics(in: proxy.size)

            ZStack(alignment: .topLeading) {
                // 兜底底色与图边缘同色，切换深浅或首帧解码时不会闪白。
                Theme.Scenery.backdrop

                sceneryImage("scenery_background_light", metrics: metrics)
                    .opacity(colorScheme == .dark ? 0 : 1)
                sceneryImage("scenery_background_dark", metrics: metrics)
                    .opacity(colorScheme == .dark ? 1 : 0)

                // 高对比度：用底色薄雾压低纹理，让前景内容更突出。
                if contrast == .increased {
                    Theme.Scenery.backdrop.opacity(0.2)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: colorScheme)
        }
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func sceneryImage(_ name: String, metrics: SceneryLayout.Metrics) -> some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .frame(width: metrics.scaledSize.width, height: metrics.scaledSize.height)
            .offset(x: metrics.origin.x, y: metrics.origin.y)
    }
}

#Preview {
    SceneryBackgroundView()
}
