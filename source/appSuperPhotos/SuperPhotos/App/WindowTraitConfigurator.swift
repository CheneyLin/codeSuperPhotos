import SwiftUI
import UIKit

/// 把 App 内的“高对比度”开关写入窗口 trait，
/// 让 Theme 中的 UIColor 动态色与系统组件一起切换到高对比色板。
struct WindowTraitConfigurator: UIViewRepresentable {
    let highContrast: Bool

    func makeUIView(context: Context) -> TraitView {
        let view = TraitView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: TraitView, context: Context) {
        uiView.highContrast = highContrast
    }

    final class TraitView: UIView {
        var highContrast = false {
            didSet { applyTrait() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyTrait()
        }

        private func applyTrait() {
            guard #available(iOS 17.0, *) else { return }
            window?.traitOverrides.accessibilityContrast = highContrast ? .high : .unspecified
        }
    }
}

/// 把 App 内偏好写回环境。
/// 高对比度通过窗口 trait 生效（同时驱动 UIColor 动态色与 SwiftUI 的 colorSchemeContrast）；
/// 降低动效没有系统 trait 可写，使用自定义环境键。
struct SettingsEnvironmentModifier: ViewModifier {
    let settings: AppSettings

    func body(content: Content) -> some View {
        content
            .environment(\.appReduceMotion, settings.reduceMotion)
    }
}
