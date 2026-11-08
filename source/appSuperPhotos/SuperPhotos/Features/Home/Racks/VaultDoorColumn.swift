import SwiftUI

/// 左侧保险箱实体列：只露出箱门，照片左滑时门打开、照片飞入。
struct VaultDoorColumn: View {
    let width: CGFloat
    let count: Int
    let isConfigured: Bool
    /// 门是否打开；由外部在“存入”动作的同一时刻置位。
    let isOpen: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }
    private var compact: Bool { width < 88 }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button(action: onTap) {
                doorStack
            }
            .buttonStyle(.plain)
            .accessibilityLabel("私密保险箱，已存 \(count) 件")
            .accessibilityHint("点按查看预览，解锁后可管理")

            Text("保险箱")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Text.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: width)
    }

    // MARK: - 门

    private var doorStack: some View {
        ZStack(alignment: .leading) {
            cavity
            doorPanel
                .rotation3DEffect(
                    .degrees(isOpen ? -78 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .leading,
                    perspective: reduceMotion ? 0 : 0.6
                )
                .shadow(
                    color: .black.opacity(isOpen ? 0.28 : 0.12),
                    radius: isOpen ? 14 : 6,
                    x: isOpen ? 8 : 2,
                    y: 4
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.Shadow.insetBorder, lineWidth: 1)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.14) : .easeOut(duration: 0.28),
            value: isOpen
        )
    }

    /// 门后腔体：门开时可见，暗示“里面能放东西”。
    private var cavity: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.88), Theme.Surface.sunken],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: Theme.Spacing.sm) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.Accent.brass.opacity(0.35))
                    .frame(height: 3)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.Accent.brass.opacity(0.22))
                    .frame(height: 3)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
        }
    }

    private var doorPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Theme.Accent.brass.opacity(0.92),
                            Theme.Accent.brass.opacity(0.62),
                            Theme.Accent.brass.opacity(0.86)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                      )
                )

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.Shadow.raisedBorder, lineWidth: 1)
                .padding(1)

            VStack(spacing: compact ? 8 : 14) {
                dial
                    .frame(width: compact ? 26 : 34, height: compact ? 26 : 34)

                if !compact {
                    Text("SUPER")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(Theme.Surface.base.opacity(0.9))
                }

                Spacer(minLength: 0)

                countBadge
            }
            .padding(.vertical, compact ? 10 : 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dial: some View {
        ZStack {
            Circle()
                .fill(Theme.Surface.raised)
                .shadow(color: Theme.Shadow.dark.opacity(0.7), radius: 3, x: 1.5, y: 1.5)
                .shadow(color: Theme.Shadow.highlight, radius: 3, x: -1.5, y: -1.5)

            Circle()
                .strokeBorder(Theme.Accent.brass.opacity(0.8), lineWidth: 1.2)
                .padding(3)

            Image(systemName: isConfigured ? "lock.fill" : "lock.open")
                .font(.system(size: compact ? 9 : 11, weight: .semibold))
                .foregroundStyle(Theme.Accent.brass)
        }
    }

    private var countBadge: some View {
        VStack(spacing: 0) {
            Text("\(min(count, 99))")
                .font(.system(size: compact ? 13 : 15, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.Surface.base)
            Text("件")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Theme.Surface.base.opacity(0.72))
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        VaultDoorColumn(width: 78, count: 5, isConfigured: true, isOpen: false, onTap: {})
        VaultDoorColumn(width: 78, count: 5, isConfigured: true, isOpen: true, onTap: {})
        VaultDoorColumn(width: 148, count: 0, isConfigured: false, isOpen: false, onTap: {})
    }
    .frame(height: 360)
    .padding()
    .background(Theme.Surface.base)
}
