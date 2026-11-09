import SwiftUI

/// 首次引导：五区说明 / 销毁玩法 / 保险箱，可跳过。
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion
    @State private var page = 0

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "rectangle.stack",
            title: "从桌面开始一批",
            subtitle: "桌面不展示照片，选一个相簿，一次最多整理 \(TaskPolicy.batchSize) 张。",
            items: [
                .init("photo.stack", "选择相簿", "「全部照片」或任意自建相簿，按顺序逐张处理。"),
                .init("photo", "中央舞台", "四张堆叠，轻点全屏，双指缩放。"),
                .init("sidebar.left", "左右抽屉", "左侧保险箱预览，右侧相簿列表。"),
                .init("flame", "底部机器", "壁炉与碎纸机，选择删除方式。")
            ]
        ),
        OnboardingPage(
            symbol: "flame",
            title: "先入队，任务结束统一处理",
            subtitle: "下滑只加入本批待销毁，不会立刻删除系统照片。",
            items: [
                .init("hand.draw", "下滑照片", "超过 \(Int(StageStackPolicy.discardCommitDistance))pt 才计入，不足会弹回原位。"),
                .init("flame", "飞入处理口", "照片飞进底部炉口或刀口，粒子里消失。"),
                .init("checkmark.circle", "统一结算", "一批处理完才加密保险箱、删除废纸篓。"),
                .init("arrow.uturn.backward", "系统确认", "不可逆操作由系统确认框把关；取消不会留下重复副本。")
            ]
        ),
        OnboardingPage(
            symbol: "lock.shield",
            title: "保险箱只在本机",
            subtitle: "不想被随手翻到的照片，复制一份到 App 沙盒。",
            items: [
                .init("lock.doc", "本地副本", "不联网、不上传，钥匙只在本机。"),
                .init("circle.grid.3x3", "密码盘", "转动内外两圈组合，支持 VoiceOver 调节。"),
                .init("clock.badge.checkmark", "自动锁定", "切到后台立即上锁，可设置延迟。"),
                .init("exclamationmark.triangle", "无法找回", "忘记组合只能重置保险箱。")
            ]
        )
    ]

    var body: some View {
        ZStack {
            Theme.Surface.base.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageView(pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(
                    Theme.Motion.animation(.standard, reduceMotion: reduceMotion),
                    value: page
                )

                dots
                footerButton
            }
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

            Button("跳过") {
                onFinish()
            }
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundStyle(Theme.Text.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal, Theme.Spacing.sm)
            .accessibilityHint("跳过引导，直接进入主界面")
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.sm)
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                ZStack {
                    Circle()
                        .fill(Theme.Surface.sunken)
                        .frame(width: 96, height: 96)
                    Image(systemName: page.symbol)
                        .font(.system(size: 38, weight: .regular))
                        .foregroundStyle(Theme.Accent.fire)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(page.title)
                        .font(Theme.Typography.largeTitle)
                        .foregroundStyle(Theme.Text.primary)
                    Text(page.subtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: Theme.Spacing.md) {
                    ForEach(Array(page.items.enumerated()), id: \.offset) { _, item in
                        itemRow(item)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.lg)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(page.title)。\(page.subtitle)")
    }

    private func itemRow(_ item: OnboardingPage.Item) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: item.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Accent.fire)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.Surface.sunken)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Text.primary)
                Text(item.detail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuSurface(.raisedSmall, cornerRadius: Theme.Radius.card)
        .accessibilityElement(children: .combine)
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
        .accessibilityLabel("第 \(page + 1) 页，共 \(pages.count) 页")
    }

    private var footerButton: some View {
        Button {
            if page < pages.count - 1 {
                page += 1
            } else {
                onFinish()
            }
        } label: {
            Text(page < pages.count - 1 ? "下一步" : "开始整理")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(NeuButtonStyle(variant: .raised, tint: Theme.Accent.fire))
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.bottom, Theme.Spacing.xl)
        .accessibilityHint(page < pages.count - 1 ? "进入下一页" : "完成引导并进入主界面")
    }
}

private struct OnboardingPage {
    struct Item {
        let symbol: String
        let title: String
        let detail: String

        init(_ symbol: String, _ title: String, _ detail: String) {
            self.symbol = symbol
            self.title = title
            self.detail = detail
        }
    }

    let symbol: String
    let title: String
    let subtitle: String
    let items: [Item]
}

#Preview {
    OnboardingView {}
}
