//
//  DuoDevice.swift
//  SuperPhotos
//
//  移植来源：codeSuperLiveWallpaper/Source/superLiveWallpaper/superLiveWallpaper/Model/DuoDevice.swift
//            （Changyu Lin，2026/11/6）
//
//  iPhone Duo 折叠状态识别：iOS 27.1+ 公开铰链 API + 低版本兜底。
//
//  原则：
//  1. 用铰链状态 / 布局特征判断，不硬编码机型与屏幕尺寸。
//  2. SDK 提供 onHingeChange(old,new) / DeviceHinge.status(.closed/.partiallyOpen/.fullyOpen) /
//     GeometryProxy.reservedRegions(kind: .division)；没有 isLaptopPose 环境变量、
//     没有 context.display.isInnerDisplay，书本姿态与内外屏都由铰链状态推导。
//  3. 本包只做「状态注入 + 布局工具」，不驱动任何现有页面分支；一期布局仍按宽度自适应。
//
//  与参考实现的差异：
//  - 去掉了原项目写在 UIUtil.swift 里的全局可变变量 DeviceDuoType / DeviceDuoOrientation，
//    所有状态都走 Environment，避免 Swift 并发隔离问题与跨模块隐式耦合。
//  - 状态由「铰链状态 + 布局快照」两个原始量统一推导（make(hingeState:layout:)），
//    修掉原实现 isLaptopPose / hingeActive 依赖多条 onChange 链导致的滞留问题。
//  - 铰链状态变化时主动重读 division 区域（hingeToken），不再只依赖 geo.size 变化。
//

import SwiftUI

// MARK: - 统一状态模型（全项目复用）

enum DuoHingeState: String, Equatable, Sendable {
    /// 不是折叠设备（普通 iPhone / iPad），或 iOS < 27.1 无铰链 API
    case notDuo
    /// 闭合：使用外屏
    case closed
    /// 半开：书本姿态候选，铰链分割区激活
    case partiallyOpen
    /// 完全展平 180°，内屏全屏
    case fullyOpen

    var label: String {
        switch self {
        case .notDuo:        return "普通设备".localized
        case .closed:        return "外屏 · 闭合".localized
        case .partiallyOpen: return "半开 · 书本".localized
        case .fullyOpen:     return "内屏 · 全开".localized
        }
    }
}

struct DuoDeviceInfo: Equatable, Sendable {
    var hingeState: DuoHingeState = .notDuo
    /// 书本姿态。以铰链状态为权威值：partiallyOpen 即书本姿态；
    /// division 区域只用于遮挡带避让，不再参与姿态判定（见适配文档踩坑 4.3）。
    var isLaptopPose: Bool = false
    /// 当前渲染于内屏：铰链存在且非闭合
    var isInnerScreen: Bool = false
    /// division 遮挡带是否存在（只读快照，供布局避让判断）
    var hingeActive: Bool = false

    // 内屏横竖屏，仅 isInnerScreen = true 时有效
    var innerIsLandscape: Bool = false
    var innerIsPortrait: Bool = false

    /// 外屏（闭合态）
    var isOuterScreen: Bool { hingeState == .closed }
    /// 是否 Duo 设备（铰链 API 报告过有效状态）
    var isDuo: Bool { hingeState != .notDuo }

    var posture: String {
        guard isDuo else { return "非 Duo".localized }
        if isOuterScreen { return "外屏".localized }
        if isLaptopPose {
            return innerIsLandscape ? "书本 · 横".localized : "书本 · 竖".localized
        }
        return innerIsLandscape ? "内屏 · 横".localized : "内屏 · 竖".localized
    }

    /// 唯一入口：由原始量推导全部派生状态，避免多条 onChange 链互相覆盖。
    static func make(hingeState: DuoHingeState, layout: DuoLayoutInfo) -> DuoDeviceInfo {
        var info = DuoDeviceInfo()
        info.hingeState = hingeState
        info.hingeActive = layout.hingeBand != nil
        info.isInnerScreen = (hingeState == .partiallyOpen || hingeState == .fullyOpen)
        info.isLaptopPose = (hingeState == .partiallyOpen)
        if info.isInnerScreen {
            info.innerIsLandscape = layout.isLandscape
            info.innerIsPortrait = layout.isPortrait
        }
        return info
    }
}

// MARK: - Environment

private struct DuoInfoKey: EnvironmentKey {
    static let defaultValue = DuoDeviceInfo()
}

extension EnvironmentValues {
    /// 铰链姿态。任何视图都可以 `@Environment(\.duoInfo) var duo` 读取；
    /// iOS < 27.1 / 非 Duo 设备恒为默认值（.notDuo）。
    var duoInfo: DuoDeviceInfo {
        get { self[DuoInfoKey.self] }
        set { self[DuoInfoKey.self] = newValue }
    }
}

// MARK: - 根节点包装

/// 版本兼容包装：iOS 27.1+ 注入铰链状态与布局快照，低版本 / 非 Duo 设备
/// 仍然渲染原布局（`duoInfo` 保持 .notDuo），现有页面无需任何改动。
///
/// 用法：`DuoGate { HomeView() ... }`，与参考项目 superLiveWallpaperApp 一致。
struct DuoGate<Content: View>: View {
    @ViewBuilder let content: Content

    @State private var hingeState: DuoHingeState = .notDuo
    @State private var layout = DuoLayoutInfo()
    /// 铰链状态变化时自增，强制 background 里的 GeometryReader 重读 division 区域。
    @State private var hingeToken = 0

    private var effectiveLayout: DuoLayoutInfo {
        #if DEBUG
        if let orientation = DuoDebugOverride.bandOrientation, orientation != .none {
            var next = layout
            next.hingeBand = DuoLayoutMetrics.simulatedBand(orientation, in: layout.containerSize)
            return next
        }
        #endif
        return layout
    }

    private var effectiveInfo: DuoDeviceInfo {
        #if DEBUG
        if let simulated = DuoDebugOverride.hingeState {
            return DuoDeviceInfo.make(hingeState: simulated, layout: effectiveLayout)
        }
        #endif
        return DuoDeviceInfo.make(hingeState: hingeState, layout: effectiveLayout)
    }

    var body: some View {
        content
            .environment(\.duoInfo, effectiveInfo)
            .environment(\.duoLayout, effectiveLayout)
            .modifier(DuoHingeChangeModifier { state in
                // 高频角度回调：只有状态真正变化才写入，天然防抖
                if hingeState != state { hingeState = state }
                hingeToken &+= 1
            })
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { readLayout(geo) }
                        .onChange(of: geo.size) { _, _ in readLayout(geo) }
                        .onChange(of: hingeToken) { _, _ in readLayout(geo) }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }

    private func readLayout(_ geo: GeometryProxy) {
        let next = DuoLayoutMetrics.read(from: geo)
        if next != layout { layout = next }
    }
}

/// 把 27.1+ 的铰链回调隔离在 modifier 内，DuoGate 本身不携带可用性标记。
private struct DuoHingeChangeModifier: ViewModifier {
    let onChange: (DuoHingeState) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, new in
                guard let hinge = new.hinge else {
                    onChange(.notDuo)
                    return
                }
                // Status 是带静态常量的结构体（不是枚举），必须用 == 分派
                let status = hinge.status
                let state: DuoHingeState
                if status == .closed {
                    state = .closed
                } else if status == .partiallyOpen {
                    state = .partiallyOpen
                } else if status == .fullyOpen {
                    state = .fullyOpen
                } else {
                    state = .notDuo
                }
                onChange(state)
            }
        } else {
            content
        }
    }
}
