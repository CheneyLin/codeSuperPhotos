import CoreGraphics

/// 延后（snooze）参数：上滑距离与甩动力度共同映射到 1–30 天。
/// 曲线与阈值集中在这里，调整手感只改本文件。
enum SnoozePolicy {
    static let minDays = 1
    static let maxDays = 30
    /// 上滑提交阈值：不足则弹簧回弹，不落库。
    /// 适度下调以贴合更长的「1 天」区域，轻滑即可延后 1 天。
    static let commitDistance: CGFloat = 64
    /// 甩动预测距离的权重：手指快、位移短时也能落到更长的延后天数。
    static let flickWeight: CGFloat = 0.55
    /// 映射曲线：位移达到该值时取满 30 天。
    static let fullRangeDistance: CGFloat = 320
    /// 映射曲线起点（死区）：小于该位移统一按 1 天。调大可加长「1 天」区域。
    static let curveFloor: CGFloat = 44
    /// 跟手阶段照片的最大上移距离，超出按阻尼。
    static let stretchLimit: CGFloat = 220
    /// 曲线指数：>1 时前段天数增长慢、后段快（凹向上），让「1 天」区域更长、长延后更易拉到。
    static let curveExponent: CGFloat = 2.0

    /// `translation` / `predicted` 均为向上滑动的正距离。
    /// 距离负责“拉到哪里”，甩动预测（含速度）负责“甩得多狠”，取较大者。
    static func days(translation: CGFloat, predicted: CGFloat) -> Int {
        let reach = max(translation, predicted * flickWeight)
        let span = max(1, fullRangeDistance - curveFloor)
        let linearNorm = min(1, max(0, (reach - curveFloor) / span))
        // 凹向上曲线：起点平缓（1 天区域更长），末端陡峭（长延后更易拉到）。
        let curved = pow(linearNorm, curveExponent)
        let value = minDays + Int((curved * CGFloat(maxDays - minDays)).rounded())
        return min(maxDays, max(minDays, value))
    }
}
