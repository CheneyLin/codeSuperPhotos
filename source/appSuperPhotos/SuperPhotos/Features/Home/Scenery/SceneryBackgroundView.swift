import SwiftUI
import UIKit

/// 背景成品图的几何：所有落点都按同一份比例计算，保证内容与图中的桌面、洞洞板对齐。
/// 宽高比直接读真实素材，换图后不需要再改任何比例常量。
enum SceneryLayout {
    /// 资源读不到时的兜底尺寸（官方成品图 1088×2368）。aspectFill (cover) 只依赖宽高比，
    /// @2x/@3x 的点尺寸不影响结果。
    static let defaultImageSize = CGSize(width: 1088, height: 2368)

    /// 桌面上沿（相对图高）。不再参与行高计算，只给 HUD 诊断台面线位置用。
    static let benchTopRatio: CGFloat = 0.828

    struct Metrics {
        /// aspectFill (cover) 后的绘制尺寸（≥ 容器，超出部分居中裁切）
        var scaledSize: CGSize
        /// 图片左上角在容器中的位置：x 为横向居中裁掉的部分（负值），y 恒为 0。
        var origin: CGPoint
        /// 桌面上沿在容器坐标中的落点（可能在容器外，仅供诊断）
        var benchTopY: CGFloat
    }

    /// 取真实素材尺寸；找不到资源时回退兜底尺寸，不会让背景变成 0×0。
    static func imageSize(forAsset name: String) -> CGSize {
        guard let image = UIImage(named: name),
              image.size.width > 0, image.size.height > 0 else {
            return defaultImageSize
        }
        return image.size
    }

    /// 适配策略：等比 aspectFill（cover）—— 铺满容器、不变形（不拉伸）；
    /// 超出容器的部分等比居中裁切。即「cover」的标准语义：填满 + 等比 + 居中裁切，
    /// 与 `scaledToFill`（拉伸变形）不同，本实现始终保持原图宽高比。
    static func metrics(in size: CGSize, imageSize: CGSize = defaultImageSize) -> Metrics {
        guard size.width > 0, size.height > 0,
              imageSize.width > 0, imageSize.height > 0 else {
            return Metrics(scaledSize: .zero, origin: .zero, benchTopY: size.height)
        }

        // cover：取「能铺满容器」的最小等比缩放，scale ≥ 任一方向比例（至少一个方向刚好填满）。
        let scale = max(size.width / imageSize.width, size.height / imageSize.height)
        let scaledW = imageSize.width * scale
        let scaledH = imageSize.height * scale
        // 居中裁切：图片左上角落在容器中央，四周均匀溢出被裁掉（origin 为负 = 往外偏移）。
        let origin = CGPoint(x: (size.width - scaledW) / 2,
                             y: (size.height - scaledH) / 2)

        return Metrics(
            scaledSize: CGSize(width: scaledW, height: scaledH),
            origin: origin,
            benchTopY: benchTopRatio * scaledH
        )
    }
}

/// 主界面的实体场景外壳：墙面 + 洞洞板 + 木桌的成品位图。
/// 浅 / 深两张图按 `DeviceLayoutConfig` 当前形态取用，共用 `SceneryLayout.metrics`。
/// 纯装饰层，不参与命中测试，也不承载任何业务状态。
struct SceneryBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion
    @Environment(\.duoInfo) private var duo

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    var body: some View {
        GeometryReader { proxy in
            let entry = DeviceLayoutConfig.current(duo: duo, size: proxy.size)
            let metrics = entry.sceneryMetrics(in: proxy.size)

            ZStack(alignment: .topLeading) {
                // 兜底底色与图边缘同色，切换深浅或首帧解码时不会闪白。
                Theme.Scenery.backdrop

                sceneryImage(entry.background.light, metrics: metrics)
                    .opacity(colorScheme == .dark ? 0 : 1)
                sceneryImage(entry.background.dark, metrics: metrics)
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
        Image(resolvedName(name))
            .resizable()
            .interpolation(.high)
            .frame(width: metrics.scaledSize.width, height: metrics.scaledSize.height)
            // cover 居中：origin 为「容器中央」偏移，超出部分四周均匀裁切、等比不拉伸。
            .offset(x: metrics.origin.x, y: metrics.origin.y)
    }

    /// 配置的 asset 名写错 / 图还没导入时回退官方成品图，避免整块背景空白。
    /// 深色位按名字是否以 `_dark` 结尾判断，自定义命名只要对应即可。
    private func resolvedName(_ name: String) -> String {
        if UIImage(named: name) != nil { return name }
        return name.hasSuffix("_dark")
            ? SceneryAssets.standard.dark
            : SceneryAssets.standard.light
    }
}

#Preview {
    SceneryBackgroundView()
}
