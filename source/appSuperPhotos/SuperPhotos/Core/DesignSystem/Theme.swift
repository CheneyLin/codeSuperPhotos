import SwiftUI
import UIKit

/// 全局设计 token：颜色、圆角、间距、描边。
/// 业务页面只引用这里的 token，不自行拼颜色与阴影。
enum Theme {

    // MARK: - 颜色

    enum Surface {
        /// 页面底色
        static let base = dynamic(
            light: 0xE8EBEF, dark: 0x1E2227,
            lightHighContrast: 0xF7F8FA, darkHighContrast: 0x101215
        )
        /// 凸起表面
        static let raised = dynamic(
            light: 0xEDF0F4, dark: 0x262B31,
            lightHighContrast: 0xFFFFFF, darkHighContrast: 0x2E343B
        )
        /// 凹陷表面
        static let sunken = dynamic(
            light: 0xE2E6EB, dark: 0x191C21,
            lightHighContrast: 0xE8ECF0, darkHighContrast: 0x0A0C0E
        )
        /// 纯白按钮底：作为实体道具，深浅模式都保持白色。
        static let pill = dynamic(
            light: 0xFFFFFF, dark: 0xFFFFFF,
            lightHighContrast: 0xFFFFFF, darkHighContrast: 0xFFFFFF
        )
    }

    enum Text {
        static let primary = dynamic(
            light: 0x2B313A, dark: 0xE7EBF0,
            lightHighContrast: 0x101418, darkHighContrast: 0xFFFFFF
        )
        static let secondary = dynamic(
            light: 0x5B6672, dark: 0xA7B1BC,
            lightHighContrast: 0x333B44, darkHighContrast: 0xD6DDE4
        )
        /// 纯白胶囊按钮上的文字：白底在深浅模式都不变，文字固定用深色保证对比度。
        static let onWhite = dynamic(
            light: 0x2B313A, dark: 0x242A32,
            lightHighContrast: 0x101418, darkHighContrast: 0x101418
        )
        static let tertiary = dynamic(
            light: 0x7A8591, dark: 0x6F7A86,
            lightHighContrast: 0x454E58, darkHighContrast: 0xB3BCC6
        )
    }

    enum Accent {
        /// 壁炉火焰
        static let fire = dynamic(
            light: 0xE4693A, dark: 0xFF7A45,
            lightHighContrast: 0xB9471A, darkHighContrast: 0xFF9A6B
        )
        /// 余烬
        static let ember = dynamic(
            light: 0xC2410C, dark: 0xE2552B,
            lightHighContrast: 0x8F2D06, darkHighContrast: 0xFF8254
        )
        /// 碎纸机金属
        static let metal = dynamic(
            light: 0x7C8794, dark: 0x9AA6B2,
            lightHighContrast: 0x4E5964, darkHighContrast: 0xCBD4DE
        )
        /// 保险箱黄铜
        static let brass = dynamic(
            light: 0xB08D57, dark: 0xC9A26B,
            lightHighContrast: 0x7A5B2E, darkHighContrast: 0xEBC994
        )
    }

    /// 拍立得相纸：亮色用暖白、暗色用近黑，边距颜色跟随主题，避免暗色下白纸刺眼。
    enum Polaroid {
        static let paper = dynamic(
            light: 0xFBF8F1, dark: 0x1A1D21,
            lightHighContrast: 0xFFFFFF, darkHighContrast: 0x0D0E10
        )
        static let edge = dynamic(
            light: 0xC9C1B2, dark: 0x2E343B,
            lightAlpha: 0.55, darkAlpha: 0.9,
            lightHighContrast: 0x8A8375, darkHighContrast: 0x4A515A
        )
        /// 相纸圆角：比旧版 6pt 更圆润
        static let corner: CGFloat = 14
        /// 相纸内照片圆角
        static let photoCorner: CGFloat = 9
        /// 相纸投影
        static let shadow = dynamic(
            light: 0x2B1E12, dark: 0x000000,
            lightAlpha: 0.22, darkAlpha: 0.55,
            lightHighContrast: 0x1A1108, darkHighContrast: 0x000000,
            lightHighContrastAlpha: 0.30, darkHighContrastAlpha: 0.65
        )
    }

    /// 场景化桌面：成品背景图的兜底色与道具配色。
    /// 仅用于主界面外壳，不参与业务语义。
    enum Scenery {
        /// 背景图边缘的近似色：首帧与切换深浅时兜底，避免闪白。
        static let backdrop = dynamic(
            light: 0xF7E9D6, dark: 0x252A33,
            lightHighContrast: 0xFCF3E5, darkHighContrast: 0x14171D
        )
        /// 木桌面（纸篓落在桌下的投影）
        static let desk = dynamic(
            light: 0xC99B67, dark: 0x4A3728,
            lightHighContrast: 0xB98449, darkHighContrast: 0x5A4433
        )
        /// 挂钩金属
        static let hook = dynamic(
            light: 0xB3A38B, dark: 0x707C88,
            lightHighContrast: 0x8E7C5F, darkHighContrast: 0x9BA7B3
        )
        /// 天蓝高光（选中描边、开始按钮辉光）
        static let sky = dynamic(
            light: 0x4E9FE0, dark: 0x6CBEF7,
            lightHighContrast: 0x2F7FBF, darkHighContrast: 0x9AD8FF
        )
    }

    enum State {
        static let success = dynamic(
            light: 0x3F8F6B, dark: 0x57B08A,
            lightHighContrast: 0x1F664A, darkHighContrast: 0x7ADDB4
        )
        static let danger = dynamic(
            light: 0xC0453C, dark: 0xE06B60,
            lightHighContrast: 0x8F211A, darkHighContrast: 0xFF9A8F
        )
    }

    // MARK: - 阴影

    enum Shadow {
        /// 右下暗影；暗色模式下加深
        static let dark = dynamic(
            light: 0xA3B1C6, dark: 0x000000,
            lightAlpha: 0.55, darkAlpha: 0.62,
            lightHighContrast: 0x6E7C8D, darkHighContrast: 0x000000,
            lightHighContrastAlpha: 0.65, darkHighContrastAlpha: 0.75
        )
        /// 左上高光；暗色模式下极弱
        static let highlight = dynamic(
            light: 0xFFFFFF, dark: 0xFFFFFF,
            lightAlpha: 0.95, darkAlpha: 0.055,
            lightHighContrast: 0xFFFFFF, darkHighContrast: 0xFFFFFF,
            lightHighContrastAlpha: 1, darkHighContrastAlpha: 0.10
        )
        /// 凹陷的内描边
        static let insetBorder = dynamic(
            light: 0xB9C3CF, dark: 0x0C0E11,
            lightAlpha: 0.55, darkAlpha: 0.6,
            lightHighContrast: 0x7C8A9A, darkHighContrast: 0x000000,
            lightHighContrastAlpha: 0.70, darkHighContrastAlpha: 0.75
        )
        /// 凸起的外描边（暗色下依赖它保住形体）
        static let raisedBorder = dynamic(
            light: 0xFFFFFF, dark: 0xFFFFFF,
            lightAlpha: 0.35, darkAlpha: 0.09,
            lightHighContrast: 0xFFFFFF, darkHighContrast: 0xFFFFFF,
            lightHighContrastAlpha: 0.70, darkHighContrastAlpha: 0.16
        )
    }

    // MARK: - 圆角

    enum Radius {
        static let chip: CGFloat = 8
        static let card: CGFloat = 14
        static let stage: CGFloat = 20
        static let dock: CGFloat = 28
        static let drawer: CGFloat = 32
        static let sheet: CGFloat = 32
        static func capsule(height: CGFloat) -> CGFloat { height / 2 }
    }

    // MARK: - 间距

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        /// 页面统一边距
        static let page: CGFloat = 16
    }

    enum Metrics {
        /// 最小点击区
        static let minTouchTarget: CGFloat = 44
        /// 舞台卡片左右内边距
        static let stageInset: CGFloat = 12
        /// 抽屉最大宽度
        static let drawerMaxWidth: CGFloat = 320
        /// 废纸篓相对布局位置的下移量。短屏上由 `dockBottomClearance` 收敛，
        /// 避免把纸篓推出屏幕。
        static let dockDrop: CGFloat = 40
        /// 纸篓下移后仍保留在屏幕内的最小净空（含 Home indicator 区）。
        static let dockBottomClearance: CGFloat = 12
    }

    /// 保险箱房间的三列紧密网格。
    enum VaultGrid {
        /// 固定三列：桌面与 iPad 都不改列数，保持“一行三个”的浏览节奏。
        static let columnCount = 3
        /// 1 个物理像素：3x 屏 0.33pt、2x 屏 0.5pt。
        static let lineWidth: CGFloat = 1 / UIScreen.main.scale
        /// 分隔线：亮色用深墨低透明度，暗色用白色低透明度；高对比模式加深。
        static let separator = dynamic(
            light: 0x2B313A, dark: 0xFFFFFF,
            lightAlpha: 0.12, darkAlpha: 0.14,
            lightHighContrast: 0x101418, darkHighContrast: 0xFFFFFF,
            lightHighContrastAlpha: 0.26, darkHighContrastAlpha: 0.30
        )
    }

    // MARK: - 工具

    /// 生成本身适配明暗模式的动态颜色；高对比色未提供时沿用普通色。
    static func dynamic(
        light: UInt32,
        dark: UInt32,
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat = 1,
        lightHighContrast: UInt32? = nil,
        darkHighContrast: UInt32? = nil,
        lightHighContrastAlpha: CGFloat? = nil,
        darkHighContrastAlpha: CGFloat? = nil
    ) -> Color {
        Color(uiColor: dynamicUIColor(
            light: light,
            dark: dark,
            lightAlpha: lightAlpha,
            darkAlpha: darkAlpha,
            lightHighContrast: lightHighContrast,
            darkHighContrast: darkHighContrast,
            lightHighContrastAlpha: lightHighContrastAlpha,
            darkHighContrastAlpha: darkHighContrastAlpha
        ))
    }

    /// UIKit 侧（如 CALayer 描边）使用同一个动态色。
    static func dynamicUIColor(
        light: UInt32,
        dark: UInt32,
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat = 1,
        lightHighContrast: UInt32? = nil,
        darkHighContrast: UInt32? = nil,
        lightHighContrastAlpha: CGFloat? = nil,
        darkHighContrastAlpha: CGFloat? = nil
    ) -> UIColor {
        UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let isHighContrast = traits.accessibilityContrast == .high

            if isDark {
                let rgb = isHighContrast ? (darkHighContrast ?? dark) : dark
                let alpha = isHighContrast ? (darkHighContrastAlpha ?? darkAlpha) : darkAlpha
                return UIColor(rgb: rgb, alpha: alpha)
            }

            let rgb = isHighContrast ? (lightHighContrast ?? light) : light
            let alpha = isHighContrast ? (lightHighContrastAlpha ?? lightAlpha) : lightAlpha
            return UIColor(rgb: rgb, alpha: alpha)
        }
    }
}

extension UIColor {
    fileprivate convenience init(rgb: UInt32, alpha: CGFloat) {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255
        let green = CGFloat((rgb >> 8) & 0xFF) / 255
        let blue = CGFloat(rgb & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
