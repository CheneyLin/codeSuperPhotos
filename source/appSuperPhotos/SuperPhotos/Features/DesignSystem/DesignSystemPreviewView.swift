import SwiftUI

/// 设计系统预览：M2 验收用，同时作为后续组件的对照页。
struct DesignSystemPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isMotionSampleShifted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                paletteSection
                typographySection
                surfaceSection
                buttonSection
                motionSection
            }
            .padding(Theme.Spacing.page)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.Surface.base.ignoresSafeArea())
        .navigationTitle("设计系统".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成".localized) { dismiss() }
            }
        }
    }

    // MARK: - 色板

    private var paletteSection: some View {
        previewSection("色板".localized) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Theme.Spacing.md)], spacing: Theme.Spacing.md) {
                swatch("base", color: Theme.Surface.base)
                swatch("raised", color: Theme.Surface.raised)
                swatch("sunken", color: Theme.Surface.sunken)
                swatch("text.primary", color: Theme.Text.primary)
                swatch("text.secondary", color: Theme.Text.secondary)
                swatch("fire", color: Theme.Accent.fire)
                swatch("metal", color: Theme.Accent.metal)
                swatch("brass", color: Theme.Accent.brass)
                swatch("success", color: Theme.State.success)
                swatch("danger", color: Theme.State.danger)
            }
        }
    }

    private func swatch(_ name: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(color)
                .frame(height: 40)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .strokeBorder(Theme.Shadow.insetBorder, lineWidth: 1)
                        .opacity(0.4)
                }
            Text(name)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.secondary)
        }
    }

    // MARK: - 字体

    private var typographySection: some View {
        previewSection("字号层级".localized) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                labeledLine("Display 34", sample: "1,204 / 20,318", font: Theme.Typography.display)
                labeledLine("Title 22", sample: "整理进度".localized, font: Theme.Typography.title)
                labeledLine("Headline 17", sample: "存入保险箱".localized, font: Theme.Typography.headline)
                labeledLine("Body 15", sample: "把不想被随手翻到的照片拖进保险箱。".localized, font: Theme.Typography.body)
                labeledLine("Caption 12", sample: "最近删除保留 30 天".localized, font: Theme.Typography.caption)
                labeledLine("Dial", sample: "07 · 24", font: Theme.Typography.dialNumber)
            }
        }
    }

    private func labeledLine(_ label: String, sample: String, font: Font) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.tertiary)
            Text(sample)
                .font(font)
                .foregroundStyle(Theme.Text.primary)
        }
    }

    // MARK: - 表面

    private var surfaceSection: some View {
        previewSection("表面".localized) {
            VStack(spacing: Theme.Spacing.lg) {
                HStack(spacing: Theme.Spacing.lg) {
                    surfaceTile("Raised", style: .raised, radius: Theme.Radius.card)
                    surfaceTile("Small", style: .raisedSmall, radius: Theme.Radius.chip)
                }
                surfaceTile("Inset", style: .inset, radius: Theme.Radius.card)
                Text("规则：凸起 = 外阴影对 + 左上高光描边；凹陷 = 内阴影对 + 1pt 内描边。".localized)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Text.secondary)
            }
        }
    }

    private func surfaceTile(_ title: String, style: NeuSurfaceStyle, radius: CGFloat) -> some View {
        Text(title)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Text.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: style == .inset ? 64 : 56)
            .neuSurface(style, cornerRadius: radius)
    }

    // MARK: - 按钮

    private var buttonSection: some View {
        previewSection("按钮".localized) {
            VStack(spacing: Theme.Spacing.lg) {
                Button("开始整理".localized) {}
                    .buttonStyle(.neuPill)

                Button {
                } label: {
                    Label("存入保险箱".localized, systemImage: "lock.fill")
                }
                .buttonStyle(.neuPill)

                HStack(spacing: Theme.Spacing.lg) {
                    Button("取消".localized) {}
                        .buttonStyle(.neuInset)

                    Button {
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(NeuIconButtonStyle(tint: Theme.State.danger))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 动效

    private var motionSection: some View {
        previewSection("动效".localized) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Text("Spring 0.34 / 0.82")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Text.secondary)
                    Spacer()
                    Button(isMotionSampleShifted ? "复位".localized : "触发".localized) {
                        withAnimation(Theme.Motion.animation(.spring, reduceMotion: reduceMotion)) {
                            isMotionSampleShifted.toggle()
                        }
                    }
                    .buttonStyle(NeuButtonStyle(variant: .raisedSmall, cornerRadius: Theme.Radius.chip))
                }

                HStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Accent.fire.opacity(0.9))
                        .frame(width: 56, height: 56)
                        .offset(x: isMotionSampleShifted ? 180 : 0, y: isMotionSampleShifted ? 12 : 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 80)
                .neuSurface(.inset, cornerRadius: Theme.Radius.card)

                Text("开启系统“降低动效”后，超过 400ms 的动画自动降级为 200ms 淡出。".localized)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Text.secondary)
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    // MARK: - 容器

    private func previewSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Text.primary)
            content()
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .neuSurface(.raised, cornerRadius: Theme.Radius.sheet)
        }
    }
}

#Preview {
    NavigationStack {
        DesignSystemPreviewView()
    }
}
