//
//  DuoDiagnostics.swift
//  SuperPhotos
//
//  DEBUG 专用：Duo 状态只读 HUD + 无真机时的状态模拟。
//  铰链 API 只在真机折叠硬件上有效，模拟器不会报告任何姿态；
//  用启动环境变量可以在普通设备 / 模拟器上预演未来的布局分支。
//
//  用法（Xcode Scheme → Arguments → Environment Variables）：
//    SP_DUO_STATE = closed | partiallyOpen | fullyOpen | notDuo
//    SP_DUO_BAND  = vertical | horizontal
//    SP_DUO_DEBUG = 1        // 只显示 HUD，不模拟状态
//  约定与现有 SP_HIT_DEBUG=1 一致；Release 构建下本文件只保留一个空视图。
//

import SwiftUI

#if DEBUG

enum DuoDebugOverride {
    private static func setting(_ key: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty { return value }
        return UserDefaults.standard.string(forKey: "debug.\(key)")
    }

    /// 模拟的铰链状态；nil 表示使用真机实际状态。
    static var hingeState: DuoHingeState? {
        guard let raw = setting("SP_DUO_STATE")?.lowercased() else { return nil }
        switch raw {
        case "closed", "outer":                 return .closed
        case "partiallyopen", "partial", "book": return .partiallyOpen
        case "fullyopen", "open", "inner":       return .fullyOpen
        case "notduo", "off":                    return .notDuo
        default:                                 return nil
        }
    }

    /// 模拟的铰链遮挡带方向；nil 表示使用真机实际区域。
    static var bandOrientation: DuoHingeBandOrientation? {
        guard let raw = setting("SP_DUO_BAND")?.lowercased() else { return nil }
        switch raw {
        case "vertical", "v":   return .vertical
        case "horizontal", "h": return .horizontal
        case "none", "off":     return DuoHingeBandOrientation.none
        default:                return nil
        }
    }

    static var isDiagnosticsEnabled: Bool {
        setting("SP_DUO_DEBUG") == "1"
            || hingeState != nil
            || bandOrientation != nil
    }

    static var isSimulating: Bool {
        hingeState != nil || bandOrientation != nil
    }
}

/// 只读 HUD，不接收点击、不参与无障碍；默认完全不渲染。
struct DuoDiagnosticsHUD: View {
    @Environment(\.duoInfo) private var duo
    @Environment(\.duoLayout) private var layout

    var body: some View {
        if DuoDebugOverride.isDiagnosticsEnabled {
            VStack(alignment: .leading, spacing: 2) {
                Text("DUO \(DuoDebugOverride.isSimulating ? "· SIM" : "") · \(duo.posture)")
                Text("hinge: \(duo.hingeState.rawValue)")
                Text("inner \(yes(duo.isInnerScreen))  book \(yes(duo.isLaptopPose))  division \(yes(duo.hingeActive))")
                Text("size \(num(layout.containerSize.width))×\(num(layout.containerSize.height))  regular \(yes(layout.isRegular))")
                Text("band \(layout.bandOrientation.rawValue) \(bandFrame)")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .fixedSize()
            .padding(6)
            .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func yes(_ value: Bool) -> String { value ? "Y" : "N" }
    private func num(_ value: CGFloat) -> String { String(format: "%.0f", value) }
    private var bandFrame: String {
        guard let band = layout.hingeBand else { return "—" }
        return String(
            format: "(%.0f,%.0f %.0f×%.0f)",
            band.minX, band.minY, band.width, band.height
        )
    }
}

#else

struct DuoDiagnosticsHUD: View {
    var body: some View { EmptyView() }
}

#endif
