import SwiftUI

/// 显示模式；系统跟随由 SwiftUI 的 `preferredColorScheme(nil)` 实现。
enum DisplayMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 外观与交互偏好。写入 UserDefaults，重启后保持。
@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let displayMode = "settings.displayMode"
        static let highContrast = "settings.highContrast"
        static let reduceMotion = "settings.reduceMotion"
        static let soundEnabled = "settings.soundEnabled"
        static let defaultAlbumID = "settings.defaultAlbumID"
        static let defaultAlbumTitle = "settings.defaultAlbumTitle"
    }

    private let defaults: UserDefaults

    var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Keys.displayMode) }
    }

    /// 强制高对比：加深正文、加粗描边，并写入窗口 trait。
    var highContrast: Bool {
        didSet { defaults.set(highContrast, forKey: Keys.highContrast) }
    }

    /// 与系统“降低动效”取并集：系统开启或本开关开启都降级。
    var reduceMotion: Bool {
        didSet { defaults.set(reduceMotion, forKey: Keys.reduceMotion) }
    }

    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    /// 右侧收藏夹区的默认相簿；照片右滑时存入这里。
    private(set) var defaultAlbumID: String?
    private(set) var defaultAlbumTitle: String = "未选择"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedMode = defaults.string(forKey: Keys.displayMode).flatMap(DisplayMode.init(rawValue:))
        self.displayMode = storedMode ?? .system
        self.highContrast = defaults.bool(forKey: Keys.highContrast)
        self.reduceMotion = defaults.bool(forKey: Keys.reduceMotion)
        self.soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        self.defaultAlbumID = defaults.string(forKey: Keys.defaultAlbumID)
        self.defaultAlbumTitle = defaults.string(forKey: Keys.defaultAlbumTitle) ?? "未选择"
    }

    func setDefaultAlbum(id: String?, title: String) {
        defaultAlbumID = id
        defaultAlbumTitle = title
        defaults.set(id, forKey: Keys.defaultAlbumID)
        defaults.set(title, forKey: Keys.defaultAlbumTitle)
    }

    var preferredColorScheme: ColorScheme? {
        displayMode.colorScheme
    }
}
