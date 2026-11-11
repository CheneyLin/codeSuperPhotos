//
//  DeviceLayoutConfig.swift
//  SuperPhotos
//
//  多设备布局调整配置 —— 手工调参只需要改这一个文件。
//
//  ## 设计口径
//  - 一个「形态」= 一行配置。运行时由 `DeviceForm.current(...)` 判定当前形态，
//    背景层、收藏夹列、首页三区高度都读同一份 `DeviceLayoutEntry`，不会分叉。
//  - **没有自动模式**：不再按屏高自动把桌面拉回屏底（旧 `SceneryYOffset` 的
//    `usesDesktopAnchor`），也不再由运行时推导收藏夹行数 / 尺寸档（旧 `DisplayMode`）。
//    所有值都是这里写死的常量，看到什么就是什么。
//  - **背景图 cover 铺满（aspectFill）**：等比铺满容器、不拉伸、不变形；超出部分居中裁切。
//    不同屏幕比例靠换背景图、改三区比例适配，图始终铺满且保持原宽高比（不会拉伸变形）。
//
//  ## 三类可调项
//  1. `background`：浅 / 深两张背景成品图的 Asset Catalog 名称。
//     换图：把新图拖进 `Assets.xcassets/Scenery`（或任意目录），把这里的字符串改成
//     imageset 名即可；名字写错不会崩溃，会自动回退到 `SceneryAssets.standard`。
//     图片尺寸无需填写，运行时按 `UIImage.size` 取真实宽高比做 aspectFill（cover，等比铺满、不拉伸）。
//  2. `favorites`：`rows` = 一屏展示几个收藏夹，`iconSize` = 文件夹图标边长（pt），
//     另附标题 / 徽章字号。行数不截断真实相簿列表，滚轮仍是无限循环。
//  3. `zones`：上 / 中 / 下三区的高度权重，任意非负数、自动归一化、不要求和为 1。
//     - 上 = LCD 顶栏下沿 → 三栏行上沿的留白
//     - 中 = 三栏行（照片舞台 / 保险箱 / 收藏夹）
//     - 下 = 三栏行下沿 → 容器底（底部道具区所在带）
//     默认 `0 / 1 / 0` = 中间区占满容器，与旧的「1.44 倍被屏高钳住」效果一致。
//     例如想让三区按 1 : 7 : 2 分配，写 `ZoneRatios(top: 1, middle: 7, bottom: 2)`。
//
//  ## 不编译看图
//  `python3 design/background-v4/preview_device_layout.py`
//  —— 脚本正则读取本文件的数值，输出 `/tmp/device_layout_preview.png`。
//

import SwiftUI
import UIKit

// MARK: - 形态判定

/// 七种布局形态。Duo 以铰链状态为权威值，不靠尺寸猜；书本姿态归入内屏横 / 竖。
enum DeviceForm: String, CaseIterable, Sendable {
    case iPhonePortrait = "iPhone 竖屏"
    case iPhoneLandscape = "iPhone 横屏"
    case iPadPortrait = "iPad 竖屏"
    case iPadLandscape = "iPad 横屏"
    case duoOuterScreen = "Duo 外屏"
    case duoInnerPortrait = "Duo 内屏竖向"
    case duoInnerLandscape = "Duo 内屏横向"

    /// 唯一判定入口：`SceneryBackgroundView`、`HomeView` 都走这里。
    static func current(
        duo: DuoDeviceInfo,
        size: CGSize,
        idiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom
    ) -> DeviceForm {
        let isLandscape = size.width > size.height
        if duo.isOuterScreen { return .duoOuterScreen }
        if duo.isInnerScreen { return isLandscape ? .duoInnerLandscape : .duoInnerPortrait }
        if idiom == .pad { return isLandscape ? .iPadLandscape : .iPadPortrait }
        return isLandscape ? .iPhoneLandscape : .iPhonePortrait
    }
}

// MARK: - 配置项

/// 浅 / 深色背景成品图的 Asset Catalog 名称。
struct SceneryAssets: Equatable, Sendable {
    var light: String
    var dark: String

    static let standard = SceneryAssets(
        light: "scenery_background_light",
        dark: "scenery_background_dark"
    )
    static let duoOuter = SceneryAssets(
        light: "scenery_background_light_duo_outer",
        dark: "scenery_background_dark_duo_outer"
    )
    static let duoInnerPortrait = SceneryAssets(
        light: "scenery_background_light_duo_inner_p",
        dark: "scenery_background_dark_duo_inner_p"
    )
    static let duoInnerLandscape = SceneryAssets(
        light: "scenery_background_light_duo_inner_l",
        dark: "scenery_background_dark_duo_inner_l"
    )
}

/// 收藏夹滚轮：一屏可见行数 + 图标尺寸 + 两档字号。
struct FavoriteSettings: Equatable, Sendable {
    /// 一屏完整可见的行数（不影响真实相簿数量）。
    var rows: Int
    /// 文件夹图标边长（pt）。实际绘制仍会被栏宽与行高钳住，不会溢出右栏。
    var iconSize: CGFloat
    var titleSize: CGFloat
    var badgeSize: CGFloat
}

/// 上 / 中 / 下三区高度权重。
struct ZoneRatios: Equatable, Sendable {
    var top: CGFloat
    var middle: CGFloat
    var bottom: CGFloat

    var total: CGFloat { max(0.0001, top + middle + bottom) }
}

/// 某个形态的完整布局配置。
struct DeviceLayoutEntry: Equatable, Sendable {
    var form: DeviceForm
    var background: SceneryAssets
    var favorites: FavoriteSettings
    var zones: ZoneRatios

    /// 背景绘制与 `HomeView` 台面线诊断共用这一份几何：
    /// 用当前形态浅色图的真实宽高比做 aspectFill（cover，铺满不拉伸），换图后无需再改任何比例常量。
    func sceneryMetrics(in size: CGSize) -> SceneryLayout.Metrics {
        SceneryLayout.metrics(
            in: size,
            imageSize: SceneryLayout.imageSize(forAsset: background.light)
        )
    }
}

// MARK: - 配置表

enum DeviceLayoutConfig {
    // MARK: 可复用的尺寸档（改这里会同时影响引用它的形态）

    /// 原尺寸档：普通 iPhone 竖屏 / Duo 外屏 / Duo 内屏竖向。
    private static let compactFavorites = FavoriteSettings(
        rows: 5, iconSize: 58, titleSize: 11, badgeSize: 9
    )
    /// 放大档：任意横屏。
    private static let largeLandscapeFavorites = FavoriteSettings(
        rows: 3, iconSize: 114, titleSize: 13, badgeSize: 11
    )
    /// 放大档（保留 5 行）：iPad 竖屏。
    private static let largePortraitFavorites = FavoriteSettings(
        rows: 5, iconSize: 114, titleSize: 13, badgeSize: 11
    )
    /// DuoInnerLandscape
    private static let favoritesDuoInnerLandscape = FavoriteSettings(
        rows: 3, iconSize: 160, titleSize: 16, badgeSize: 12
    )
    /// DuoInnerPortrait
    private static let favoritesDuoInnerPortrait = FavoriteSettings(
        rows: 5, iconSize: 140, titleSize: 14, badgeSize: 12
    )

    /// 默认背景：所有形态共用官方成品图；换图时改对应形态的 `background` 即可。
    private static let standardBackground = SceneryAssets.standard

    /// 默认三区：中间区占满容器（等价于旧的 1.44 倍行高被屏高钳住后的结果）。
    /// 想给顶栏 / 道具区留出专门空间，替换成例如 `ZoneRatios(top: 1, middle: 7, bottom: 2)`。
    private static let fullMiddleZones = ZoneRatios(top: 0, middle: 1, bottom: 0)
    private static let fullMiddleZonesDuoOuter = ZoneRatios(top: 0, middle: 14, bottom: 5)
    private static let fullMiddleZonesDuoInnerLandscape = ZoneRatios(top: 0, middle: 14, bottom: 5)
    private static let fullMiddleZonesDuoInnerPortrait = ZoneRatios(top: 0, middle: 80, bottom: 20)

    // MARK: 七个形态 —— 只改下面这些数值

    static let iPhonePortrait = DeviceLayoutEntry(
        form: .iPhonePortrait,
        background: standardBackground,
        favorites: compactFavorites,
        zones: fullMiddleZones
    )

    static let iPhoneLandscape = DeviceLayoutEntry(
        form: .iPhoneLandscape,
        background: standardBackground,
        favorites: largeLandscapeFavorites,
        zones: fullMiddleZones
    )

    static let iPadPortrait = DeviceLayoutEntry(
        form: .iPadPortrait,
        background: standardBackground,
        favorites: largePortraitFavorites,
        zones: fullMiddleZones
    )

    static let iPadLandscape = DeviceLayoutEntry(
        form: .iPadLandscape,
        background: standardBackground,
        favorites: largeLandscapeFavorites,
        zones: fullMiddleZones
    )

    static let duoOuterScreen = DeviceLayoutEntry(
        form: .duoOuterScreen,
        background: SceneryAssets.duoOuter,
        favorites: largeLandscapeFavorites,
        zones: fullMiddleZonesDuoOuter
    )

    static let duoInnerPortrait = DeviceLayoutEntry(
        form: .duoInnerPortrait,
        background: SceneryAssets.duoInnerPortrait,
        favorites: favoritesDuoInnerPortrait,
        zones: fullMiddleZonesDuoInnerPortrait
    )

    static let duoInnerLandscape = DeviceLayoutEntry(
        form: .duoInnerLandscape,
        background: SceneryAssets.duoInnerLandscape,
        favorites: favoritesDuoInnerLandscape,
        zones: fullMiddleZonesDuoInnerLandscape
    )

    /// 全部形态，顺序即预览脚本 / HUD 的展示顺序。
    static let all: [DeviceLayoutEntry] = [
        iPhonePortrait, iPhoneLandscape,
        iPadPortrait, iPadLandscape,
        duoOuterScreen, duoInnerPortrait, duoInnerLandscape
    ]

    static func entry(for form: DeviceForm) -> DeviceLayoutEntry {
        all.first { $0.form == form } ?? iPhonePortrait
    }

    /// 唯一取值入口：背景视图、首页三区与收藏夹列都读同一份配置。
    static func current(
        duo: DuoDeviceInfo,
        size: CGSize,
        idiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom
    ) -> DeviceLayoutEntry {
        entry(for: DeviceForm.current(duo: duo, size: size, idiom: idiom))
    }
}
