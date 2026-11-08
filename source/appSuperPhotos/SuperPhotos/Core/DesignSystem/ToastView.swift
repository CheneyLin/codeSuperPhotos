import SwiftUI

struct ToastMessage: Identifiable, Equatable {
    enum Kind: Equatable {
        case info
        case success
        case warning
    }

    let id = UUID()
    let text: String
    var kind: Kind = .info
}

/// 轻量 Toast：顶部滑入，2.6s 后自动消失。
struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tintColor)

            Text(message.text)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: 340, alignment: .leading)
        .neuSurface(.raised, cornerRadius: Theme.Radius.card)
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }

    private var symbolName: String {
        switch message.kind {
        case .info: "info.circle"
        case .success: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        }
    }

    private var tintColor: Color {
        switch message.kind {
        case .info: Theme.Accent.brass
        case .success: Theme.State.success
        case .warning: Theme.State.danger
        }
    }
}

extension View {
    /// 统一 Toast 挂载方式；自动 2.6s 后清除。
    func toast(_ message: Binding<ToastMessage?>, topPadding: CGFloat = Theme.Spacing.sm) -> some View {
        overlay(alignment: .top) {
            if let value = message.wrappedValue {
                ToastView(message: value)
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.top, topPadding)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: value.id) {
                        try? await Task.sleep(for: .milliseconds(2600))
                        guard message.wrappedValue?.id == value.id else { return }
                        withAnimation(Theme.Motion.animation(.fast, reduceMotion: false)) {
                            message.wrappedValue = nil
                        }
                    }
            }
        }
        .animation(Theme.Motion.animation(.spring, reduceMotion: false), value: message.wrappedValue)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        ToastView(message: ToastMessage(text: "已移入系统『最近删除』，30 天内可找回", kind: .success))
        ToastView(message: ToastMessage(text: "免费版批量上限 50 张", kind: .warning))
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.Surface.base)
}
