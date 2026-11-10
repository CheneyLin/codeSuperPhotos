//
//  DuoLayout.swift
//  SuperPhotos
//
//  iPhone Duo 适配「布局准备层」：只提供常量、纯函数与环境快照，
//  当前不参与任何页面布局计算；后续做铰链避让 / 双栏时从这里取，避免散落魔法数。
//

import SwiftUI

// MARK: - 布局快照

/// 铰链遮挡带方向。竖向带（高 > 宽）→ 左右分栏；横向带（宽 > 高）→ 上下分区。
enum DuoHingeBandOrientation: String, Equatable, Sendable {
    case none
    case vertical
    case horizontal
}

/// 由根节点 GeometryReader 采集的只读布局快照，随尺寸 / 铰链带变化更新。
struct DuoLayoutInfo: Equatable {
    var containerSize: CGSize = .zero
    /// division 遮挡带在容器坐标系中的 frame；非 Duo / fullyOpen 时为 nil
    var hingeBand: CGRect? = nil

    /// 与产品方案 4.5 一致：可用宽度 ≥ 600pt 视为 Regular（Duo 内屏 / iPad）
    var isRegular: Bool { containerSize.width >= DuoLayoutMetrics.regularBreakpoint }
    var isLandscape: Bool { containerSize.width > containerSize.height }
    var isPortrait: Bool { containerSize.height > containerSize.width }

    var bandOrientation: DuoHingeBandOrientation {
        guard let band = hingeBand, band.width > 0, band.height > 0 else { return .none }
        return band.height >= band.width ? .vertical : .horizontal
    }
}

private struct DuoLayoutKey: EnvironmentKey {
    static let defaultValue = DuoLayoutInfo()
}

extension EnvironmentValues {
    /// 容器尺寸 + 铰链遮挡带。非 27.1 系统只有 containerSize 有效。
    var duoLayout: DuoLayoutInfo {
        get { self[DuoLayoutKey.self] }
        set { self[DuoLayoutKey.self] = newValue }
    }
}

// MARK: - 布局常量与工具

enum DuoLayoutMetrics {
    /// Regular / Compact 断点，与 product-plan 4.5、decision-log #7 保持一致
    static let regularBreakpoint: CGFloat = 600
    /// 铰链缝两侧的视觉留白，产品方案 4.5 的「中间 8pt 视觉分隔」
    static let hingeClearance: CGFloat = 8
    /// 内屏上舞台卡片 / 销毁坞的最大宽度（产品方案 4.5）
    static let stageMaxWidth: CGFloat = 640

    static func isRegular(width: CGFloat) -> Bool { width >= regularBreakpoint }

    /// 从 GeometryProxy 读取布局快照。27.1+ 才查询 division 区域，并且只认激活区域。
    static func read(from geo: GeometryProxy) -> DuoLayoutInfo {
        var info = DuoLayoutInfo(containerSize: geo.size)
        if #available(iOS 27.1, *) {
            info.hingeBand = geo.reservedRegions(kind: .division)
                .filter(\.isActive)
                .map(\.frame)
                .first
        }
        return info
    }

    /// 把容器按铰链带切成两块可用区域，供未来的书本姿态双栏 / 上下区布局使用。
    /// 无遮挡带时按左右 50/50 平分（对应 fullyOpen 内屏）。
    /// 返回值为容器坐标系中的两个矩形；两侧各让出 `clearance`。
    static func splitRects(
        in size: CGSize,
        band: CGRect?,
        clearance: CGFloat = hingeClearance
    ) -> (CGRect, CGRect) {
        guard let band, band.width > 0, band.height > 0 else {
            let half = size.width / 2
            return (
                CGRect(x: 0, y: 0, width: half, height: size.height),
                CGRect(x: half, y: 0, width: size.width - half, height: size.height)
            )
        }

        if band.height >= band.width {
            // 竖向铰链带 → 左右两栏
            let leftWidth = max(0, band.minX - clearance)
            let rightX = min(size.width, band.maxX + clearance)
            return (
                CGRect(x: 0, y: 0, width: leftWidth, height: size.height),
                CGRect(x: rightX, y: 0, width: max(0, size.width - rightX), height: size.height)
            )
        } else {
            // 横向铰链带 → 上下两区
            let topHeight = max(0, band.minY - clearance)
            let bottomY = min(size.height, band.maxY + clearance)
            return (
                CGRect(x: 0, y: 0, width: size.width, height: topHeight),
                CGRect(x: 0, y: bottomY, width: size.width, height: max(0, size.height - bottomY))
            )
        }
    }

    /// 可点元素是否压到铰链缝（含留白）。未来放按钮 / 手势区前用它做校验。
    static func intersectsHinge(
        _ frame: CGRect,
        band: CGRect?,
        clearance: CGFloat = hingeClearance
    ) -> Bool {
        guard let band else { return false }
        return frame.intersects(band.insetBy(dx: -clearance, dy: -clearance))
    }

    /// DEBUG 模拟用的铰链带：按当前容器尺寸在中央生成一条 8pt 带。
    /// 只是给没有 Duo 真机的开发者预演布局分支，Release 不参与。
    static func simulatedBand(
        _ orientation: DuoHingeBandOrientation,
        in size: CGSize
    ) -> CGRect? {
        guard size.width > 0, size.height > 0 else { return nil }
        let thickness = hingeClearance
        switch orientation {
        case .none:
            return nil
        case .vertical:
            return CGRect(
                x: (size.width - thickness) / 2, y: 0,
                width: thickness, height: size.height
            )
        case .horizontal:
            return CGRect(
                x: 0, y: (size.height - thickness) / 2,
                width: size.width, height: thickness
            )
        }
    }
}
