import Foundation

extension String {
    /// 本地化当前字符串（以自身作为 key 查找 Localizable.strings）。
    ///
    /// 基准 key 使用中文文案；`en.lproj` 提供英文译文，`zh-Hant.lproj` 提供繁體中文译文，
    /// `zh-Hans.lproj` 回退到中文本身（开发与源语言）。
    /// 其余语言（如设备设为日文）回退到 `CFBundleDevelopmentRegion`（en）。
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    /// 带参数的本地化。
    ///
    /// 译文模板统一使用 `%@` 占位符，按参数顺序依次填充。
    /// 之所以不用 `String(format:)`，是因为 `%@` 搭配 `Int` 会触发运行时崩溃，
    /// 而 `%ld` / `%lld` 又要求调用处区分整型与字符串；这里用 `Any` 统一处理，
    /// 既避免崩溃，也让转义后的模板可以复用同一套 key。
    func localized(_ args: Any...) -> String {
        var result = localized
        for arg in args {
            guard let range = result.range(of: "%@") else { break }
            result.replaceSubrange(range, with: String(describing: arg))
        }
        return result
    }
}
