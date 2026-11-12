import SwiftUI

/// 首次引导：三页插图 + 极简文案，可跳过。
///
/// 布局：上方插图、下方文案与按钮，整体居中于屏幕中央的一个正方形卡片内，
/// 卡片边长随设备尺寸自适应（取可用宽高较小者并封顶）。
/// 进入每一页时按「图片 → 文案 → 按钮」的顺序依次浮现。
/// 配色全部走 `Theme` 自适应 token，跟随系统明暗模式。
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion
    @State private var page = 0
    @State private var isAuthorizing = false

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            imageName: "welcome-1",
            text: "像在桌面整理照片般批量操作".localized,
            buttonTitle: "继续".localized
        ),
        OnboardingPage(
            imageName: "welcome-2",
            text: "收藏，删除，加密，极简操作快速上手".localized,
            buttonTitle: "继续".localized
        ),
        OnboardingPage(
            imageName: "welcome-3",
            text: "一切在本机完成，你的照片只属于你".localized,
            buttonTitle: "立即授权开始".localized
        )
    ]

    var body: some View {
        ZStack {
            Theme.Surface.base.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Spacer(minLength: 0)

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        OnboardingCard(
                            page: pages[index],
                            isActive: page == index,
                            reduceMotion: reduceMotion,
                            isLast: index == pages.count - 1,
                            action: { advanceOrAuthorize(from: index) }
                        )
                        .tag(index)
                        .accessibilityHidden(page != index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(
                    Theme.Motion.animation(.standard, reduceMotion: reduceMotion),
                    value: page
                )

                Spacer(minLength: 0)

                dots
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .dynamicTypeSize(.xSmall ... .accessibility5)
        .task {
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["UI_TEST_ONBOARDING_PAGE"],
               let requested = Int(raw),
               pages.indices.contains(requested) {
                page = requested
            }
            #endif
        }
    }

    private var header: some View {
        HStack {
            Text("SuperPhotos")
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(Theme.Text.tertiary)

            Spacer()

            Button("跳过".localized) {
                onFinish()
            }
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundStyle(Theme.Text.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal, Theme.Spacing.sm)
            .accessibilityHint("跳过引导，直接进入主界面".localized)
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private func advanceOrAuthorize(from index: Int) {
        if index < pages.count - 1 {
            page = index + 1
        } else {
            authorizeAndFinish()
        }
    }

    private func authorizeAndFinish() {
        guard !isAuthorizing else { return }
        isAuthorizing = true
        Task {
            _ = await AuthorizationService().requestAccess()
            isAuthorizing = false
            onFinish()
        }
    }

    private var dots: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Theme.Text.primary : Theme.Text.tertiary.opacity(0.35))
                    .frame(width: index == page ? 18 : 6, height: 6)
                    .animation(
                        Theme.Motion.animation(.fast, reduceMotion: reduceMotion),
                        value: page
                    )
            }
        }
        .padding(.vertical, Theme.Spacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 %@ 页，共 %@ 页".localized(page + 1, pages.count))
    }
}

/// 单页卡片：插图在上、文案与按钮在下，整体为正方形并居中于屏幕。
private struct OnboardingCard: View {
    let page: OnboardingPage
    let isActive: Bool
    let reduceMotion: Bool
    let isLast: Bool
    let action: () -> Void

    @State private var step: Int = 0

    var body: some View {
        GeometryReader { geo in
            let rawSide = min(geo.size.width, geo.size.height) * 0.96
            let side = min(rawSide, 560)

            VStack(spacing: 0) {
                // 插图：占上方，弹性撑开
                Image(page.imageName)
                    .resizable()
                    .scaledToFit()
                    .padding(Theme.Spacing.lg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(step >= 1 ? 1 : 0)
                    .offset(y: step >= 1 ? 0 : 16)
                    .scaleEffect(step >= 1 ? 1 : 0.97)
                    .accessibilityHidden(true)

                // 文案
                Text(page.text)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Text.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .opacity(step >= 2 ? 1 : 0)
                    .offset(y: step >= 2 ? 0 : 16)

                // 按钮
                Button(action: action) {
                    Text(page.buttonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.neuPill)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
                .padding(.horizontal, Theme.Spacing.xl)
                .opacity(step >= 3 ? 1 : 0)
                .offset(y: step >= 3 ? 0 : 16)
                .accessibilityHint(
                    isLast
                        ? "完成引导并进入主界面".localized
                        : "进入下一页".localized
                )
            }
            .frame(width: side, height: side)
            .background(
                NeuSurfaceBackground(style: .raised, cornerRadius: Theme.Radius.stage)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .task(id: isActive) {
                if isActive { runIntro() }
            }
        }
    }

    /// 进入本页时按「图片 → 文案 → 按钮」的顺序依次浮现。
    private func runIntro() {
        guard !reduceMotion else {
            step = 3
            return
        }
        step = 0
        withAnimation(.easeOut(duration: 0.38).delay(0.05)) { step = 1 }
        withAnimation(.easeOut(duration: 0.38).delay(0.30)) { step = 2 }
        withAnimation(.easeOut(duration: 0.38).delay(0.55)) { step = 3 }
    }
}

private struct OnboardingPage {
    let imageName: String
    let text: String
    let buttonTitle: String
}

#Preview {
    OnboardingView {}
}
