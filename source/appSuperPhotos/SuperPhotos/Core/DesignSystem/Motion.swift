import SwiftUI

extension Theme {
    /// 动效 token；超 400ms 的动画在“降低动效”下统一降级为 200ms 淡出。
    enum Motion {
        enum Token: CaseIterable {
            case fast
            case standard
            case spring
            case drawer
            case door

            var animation: Animation {
                switch self {
                case .fast:
                    .easeOut(duration: 0.12)
                case .standard:
                    .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24)
                case .spring:
                    .spring(response: 0.34, dampingFraction: 0.82)
                case .drawer:
                    .spring(response: 0.42, dampingFraction: 0.86)
                case .door:
                    .timingCurve(0.22, 0.9, 0.24, 1, duration: 0.7)
                }
            }

            var duration: TimeInterval {
                switch self {
                case .fast: 0.12
                case .standard: 0.24
                case .spring: 0.34
                case .drawer: 0.42
                case .door: 0.7
                }
            }
        }

        /// 依据“降低动效”开关返回可用动画。
        static func animation(_ token: Token, reduceMotion: Bool) -> Animation {
            if reduceMotion {
                return .easeOut(duration: token.duration > 0.4 ? 0.2 : token.duration)
            }
            return token.animation
        }
    }
}

// MARK: - 便捷修饰符

extension View {
    /// 带动效 token 的 value 动画；自动响应系统“降低动效”。
    func neuAnimation<V: Equatable>(_ token: Theme.Motion.Token, value: V) -> some View {
        modifier(NeuAnimationModifier(token: token, value: value))
    }
}

struct NeuAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    let token: Theme.Motion.Token
    let value: V

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    func body(content: Content) -> some View {
        content.animation(
            Theme.Motion.animation(token, reduceMotion: reduceMotion),
            value: value
        )
    }
}

// MARK: - App 内降低动效开关

private struct AppReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// App 设置里的“降低动效”；与系统开关取并集后使用。
    var appReduceMotion: Bool {
        get { self[AppReduceMotionKey.self] }
        set { self[AppReduceMotionKey.self] = newValue }
    }
}
