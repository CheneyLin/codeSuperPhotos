import SwiftUI

/// 布局探针：把三栏落点计算的中间量原样送到 HUD，避免只靠推断判断对错。
///
/// 定义在 `#if DEBUG` 之外：调用方（HomeView）不需要条件编译，
/// Release 下它只是一个不产生任何 UI 的 Preference 值。
struct LayoutProbe: Equatable {
    /// 三栏行宽（屏幕可用宽度）。
    var rowW: CGFloat = 0
    /// 三栏行高（显式给出，不再由内层 GeometryReader 反推）。
    var rowH: CGFloat = 0
    var sideW: CGFloat = 0
    var favoriteW: CGFloat = 0
    /// 中栏宽度 = rowW − 左右栏 − 间距 − 水平内边距。
    var middleW: CGFloat = 0
    /// GeometryReader 的全局起点与上下安全区（用来解释 contentTop 的两种来源）。
    var minY: CGFloat = 0
    var safeTop: CGFloat = 0
    var safeBottom: CGFloat = 0
    var contentTop: CGFloat = 0
    var contentHeight: CGFloat = 0
    /// 纸篓实测高度（内容要让出它）。
    var dockH: CGFloat = 0
    var benchTop: CGFloat = 0
    var contentBottom: CGFloat = 0
    var showsStage: Bool = false
}

struct LayoutProbeKey: PreferenceKey {
    static let defaultValue = LayoutProbe()
    static func reduce(value: inout LayoutProbe, nextValue: () -> LayoutProbe) {
        // SwiftUI 会把「没有显式上报该 key」的兄弟分支也按 defaultValue（全 0）参与 reduce。
        // 早期实现无条件 `value = nextValue()`，真实探针被最后合并进来的默认值清成 0，
        // 真机 HUD 因此显示 rowW/rowH 全 0，而 HitDebugRegionKey（字典 merge）正常。
        // 只接受有效上报：HomeView 每次都会给出正的 rowW。
        let next = nextValue()
        guard next.rowW > 0 else { return }
        value = next
    }
}

extension View {
    /// 上报布局中间量；本身不影响布局、不参与命中。
    func layoutProbe(_ probe: LayoutProbe) -> some View {
        preference(key: LayoutProbeKey.self, value: probe)
    }
}

#if DEBUG

/// 仅 DEBUG 生效的命中调试：画面叠加关键区域的可点边界，并记录最近触发的动作。
/// 打开方式：环境变量 `SP_HIT_DEBUG=1`；或在顶栏中间空白处长按 2 秒。
@Observable
final class HitDebug {
    static let shared = HitDebug()

    var isEnabled: Bool = ProcessInfo.processInfo.environment["SP_HIT_DEBUG"] == "1"
    private(set) var entries: [String] = []

    func note(_ text: String) {
        guard isEnabled else { return }
        entries.append(text)
        if entries.count > 6 { entries.removeFirst(entries.count - 6) }
    }

    func toggle() {
        isEnabled.toggle()
        entries = [isEnabled ? "命中调试：开" : "命中调试：关"]
    }
}

// MARK: - 区域登记

struct HitDebugRegionKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// 在调试 HUD 里描出这块区域的真实边界；本身不参与命中。
    func hitDebugRegion(_ name: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .allowsHitTesting(false)
                    .preference(key: HitDebugRegionKey.self, value: [name: proxy.frame(in: .global)])
            }
        }
    }
}

// MARK: - HUD

struct HitDebugHUD: View {
    let debug: HitDebug
    let regions: [String: CGRect]
    var probe: LayoutProbe?

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            ZStack(alignment: .topLeading) {
                ForEach(regions.keys.sorted(), id: \.self) { name in
                    if let rect = regions[name] {
                        Rectangle()
                            .strokeBorder(color(for: name), lineWidth: 1.5)
                            .frame(width: rect.width, height: rect.height)
                            .position(
                                x: rect.midX - origin.x,
                                y: rect.midY - origin.y
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("HIT DEBUG")
                        .font(.system(size: 9, weight: .bold))
                    ForEach(Array(debug.entries.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 9, design: .monospaced))
                    }
                }
                .foregroundStyle(.white)
                .padding(5)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                .padding(.leading, 6)
                .padding(.top, 96)

                layoutPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 96)
                    .padding(.trailing, 6)
            }
        }
        .allowsHitTesting(false)
    }

    /// 布局中间量面板：rowW / middleW / contentTop / contentHeight /
    /// 中栏实际全局 frame，逐行显示，便于真机截图核对。
    @ViewBuilder
    private var layoutPanel: some View {
        if let probe {
            VStack(alignment: .leading, spacing: 1) {
                Text("LAYOUT")
                    .font(.system(size: 9, weight: .bold))

                Text("rowW \(fmt(probe.rowW))  rowH \(fmt(probe.rowH))")
                Text("side \(fmt(probe.sideW))  fav \(fmt(probe.favoriteW))")
                Text("middleW \(fmt(probe.middleW))")
                Text("minY \(fmt(probe.minY))  safeT \(fmt(probe.safeTop))  safeB \(fmt(probe.safeBottom))")
                Text("contentTop \(fmt(probe.contentTop))  H \(fmt(probe.contentHeight))")
                Text("dock \(fmt(probe.dockH))  bench \(fmt(probe.benchTop))")
                Text("contentBottom \(fmt(probe.contentBottom))")
                Text("stage \(probe.showsStage ? "1" : "0")")
                if let rect = regions["中栏"] {
                    Text("中栏 \(fmt(rect.width))×\(fmt(rect.height)) @\(fmt(rect.minX)),\(fmt(rect.minY))")
                } else {
                    Text("中栏 未上报 frame")
                }
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.white)
            .padding(5)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func fmt(_ value: CGFloat) -> String {
        guard value.isFinite else { return "NaN" }
        return String(format: "%.1f", value)
    }

    private func color(for name: String) -> Color {
        switch name {
        case "主按钮": return .red
        case "直接结束": return .orange
        case "中栏": return .blue
        case "收藏夹滚轮": return .green
        default: return .yellow
        }
    }
}

/// 把 HUD 挂到任意视图上；开启时覆盖全屏但不接收任何事件。
struct HitDebugOverlayModifier: ViewModifier {
    @State private var debug = HitDebug.shared
    @State private var regions: [String: CGRect] = [:]
    @State private var probe: LayoutProbe?

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(HitDebugRegionKey.self) { regions = $0 }
            .onPreferenceChange(LayoutProbeKey.self) { probe = $0 }
            .overlay(alignment: .topLeading) {
                if debug.isEnabled {
                    HitDebugHUD(debug: debug, regions: regions, probe: probe)
                }
            }
    }
}

func hitDebugNote(_ text: String) {
    HitDebug.shared.note(text)
}

@discardableResult
func hitDebugToggle() -> Bool {
    HitDebug.shared.toggle()
    return HitDebug.shared.isEnabled
}

#else

import SwiftUI

extension View {
    /// Release 下为空实现，调用点不需要条件编译。
    func hitDebugRegion(_ name: String) -> some View { self }
}

/// Release 下 HUD 不挂载。
struct HitDebugOverlayModifier: ViewModifier {
    func body(content: Content) -> some View { content }
}

func hitDebugNote(_ text: String) {}
func hitDebugToggle() -> Bool { false }

#endif
