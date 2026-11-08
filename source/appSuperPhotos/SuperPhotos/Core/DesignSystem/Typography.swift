import SwiftUI

extension Theme {
    /// 字号层级：全部走 Dynamic Type，支持到 AX3。
    enum Typography {
        /// 页码、统计大数
        static let display = Font.system(.largeTitle, design: .rounded).weight(.semibold)
        /// 引导页主标题
        static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let title = Font.system(.title2, design: .rounded).weight(.semibold)
        static let headline = Font.system(.headline, design: .rounded).weight(.semibold)
        static let body = Font.system(.subheadline, design: .rounded)
        static let caption = Font.system(.caption, design: .rounded)
        /// 密码盘数字：等宽，避免转动时数字宽度变化
        static let dialNumber = Font.system(.body, design: .monospaced).weight(.medium)
    }
}

extension Text {
    func themeDisplay() -> Text { font(Theme.Typography.display) }
    func themeTitle() -> Text { font(Theme.Typography.title) }
    func themeHeadline() -> Text { font(Theme.Typography.headline) }
    func themeBody() -> Text { font(Theme.Typography.body) }
    func themeCaption() -> Text { font(Theme.Typography.caption) }
}
