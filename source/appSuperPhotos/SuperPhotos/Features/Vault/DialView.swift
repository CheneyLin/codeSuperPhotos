import SwiftUI
import UIKit

/// 机械密码盘：0...(count-1) 档，围绕盘心拖动，松手按 40% 阈值吸附。
struct DialView: View {
    let label: String
    let count: Int
    @Binding var value: Int
    var isEnabled: Bool = true
    var diameter: CGFloat = 148
    var onValueChanged: () -> Void = {}

    @State private var continuousAngle: Double = 0
    @State private var lastAngle: Double = 0
    @State private var isDragging = false
    @State private var lastHapticAt = Date.distantPast

    private var step: Double { 2 * .pi / Double(max(count, 1)) }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(label)
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(Theme.Text.secondary)

            ZStack {
                dialFace
                tickRing
                pointer
                centerKnob
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .gesture(isEnabled ? dragGesture : nil)
            .opacity(isEnabled ? 1 : 0.55)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label)密码盘")
            .accessibilityValue("\(value)")
            .accessibilityHint("范围 0 到 \(count - 1)，上下轻扫每次调整一档")
            .accessibilityAdjustableAction { direction in
                guard isEnabled else { return }
                switch direction {
                case .increment:
                    value = (value + 1) % count
                case .decrement:
                    value = (value - 1 + count) % count
                @unknown default:
                    break
                }
                syncAngleToValue()
                onValueChanged()
            }
        }
        .onAppear { syncAngleToValue() }
        .onChange(of: value) { _, _ in
            guard !isDragging else { return }
            withAnimation(Theme.Motion.animation(.fast, reduceMotion: false)) {
                continuousAngle = Double(value) * step
            }
        }
    }

    // MARK: - 视觉

    private var dialFace: some View {
        Circle()
            .fill(Theme.Surface.raised)
            .shadow(color: Theme.Shadow.dark.opacity(0.9), radius: 10, x: 6, y: 6)
            .shadow(color: Theme.Shadow.highlight, radius: 10, x: -6, y: -6)
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Theme.Shadow.raisedBorder, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .overlay {
                Circle()
                    .inset(by: 14)
                    .fill(Theme.Surface.sunken)
                    .overlay {
                        Circle()
                            .inset(by: 14)
                            .strokeBorder(Theme.Shadow.insetBorder, lineWidth: 1)
                    }
            }
            .overlay {
                Circle()
                    .inset(by: diameter * 0.28)
                    .fill(Theme.Surface.raised)
                    .shadow(color: Theme.Shadow.dark.opacity(0.7), radius: 5, x: 3, y: 3)
                    .shadow(color: Theme.Shadow.highlight, radius: 5, x: -3, y: -3)
            }
    }

    private var tickRing: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let isSelected = index == value
                Capsule(style: .continuous)
                    .fill(isSelected ? Theme.Accent.brass : Theme.Text.tertiary.opacity(0.7))
                    .frame(width: isSelected ? 2.6 : 1.4, height: isSelected ? 15 : 8)
                    .offset(y: -(diameter / 2 - 22))
                    .rotationEffect(.degrees(Double(index) / Double(count) * 360))
            }
        }
        .allowsHitTesting(false)
    }

    private var pointer: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Theme.Accent.brass, Theme.Accent.brass.opacity(0.35)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 3, height: diameter * 0.26)
            .offset(y: -diameter * 0.20)
            .rotationEffect(.degrees(continuousAngle * 180 / .pi))
            .shadow(color: .black.opacity(0.18), radius: 2, x: 1, y: 1)
            .allowsHitTesting(false)
    }

    private var centerKnob: some View {
        Text("\(value)")
            .font(Theme.Typography.dialNumber)
            .foregroundStyle(Theme.Text.primary)
            .scaleEffect(isDragging ? 1.15 : 1)
            .animation(Theme.Motion.animation(.fast, reduceMotion: false), value: isDragging)
            .monospacedDigit()
            .allowsHitTesting(false)
    }

    // MARK: - 手势

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let center = CGPoint(x: diameter / 2, y: diameter / 2)
                let dx = gesture.location.x - center.x
                let dy = gesture.location.y - center.y
                guard hypot(dx, dy) > 18 else { return }

                let angle = atan2(dx, -dy)
                if !isDragging {
                    isDragging = true
                    lastAngle = angle
                    return
                }

                var delta = angle - lastAngle
                if delta > .pi { delta -= 2 * .pi }
                if delta < -.pi { delta += 2 * .pi }
                lastAngle = angle
                continuousAngle += delta
                updateValue(animated: false)
            }
            .onEnded { _ in
                isDragging = false
                withAnimation(Theme.Motion.animation(.spring, reduceMotion: false)) {
                    continuousAngle = Double(value) * step
                }
            }
    }

    /// 40% 阈值吸附：超过一档 40% 就进位，否则留在原档。
    private func updateValue(animated: Bool) {
        let raw = continuousAngle / step
        let lower = floor(raw)
        let fraction = raw - lower
        let snapped = fraction >= 0.4 ? lower + 1 : lower
        let newValue = ((Int(snapped) % count) + count) % count
        guard newValue != value else { return }

        value = newValue
        fireHapticIfNeeded()
        onValueChanged()
    }

    private func syncAngleToValue() {
        continuousAngle = Double(value) * step
    }

    private func fireHapticIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastHapticAt) > 0.03 else { return }
        lastHapticAt = now
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

#Preview {
    HStack(spacing: 24) {
        DialView(label: "左盘 A", count: VaultCredentials.dialCount, value: .constant(7))
        DialView(label: "右盘 B", count: VaultCredentials.dialCount, value: .constant(23))
    }
    .padding(32)
    .background(Theme.Surface.base)
}
