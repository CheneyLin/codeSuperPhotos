import SwiftUI
import UIKit

// MARK: - 模型

/// 我们在 App Store 上的其他应用条目（数据来自 Features/OurApps/OurApps.plist）。
struct OurAppItem: Identifiable {
    let appID: String
    let imageName: String
    let names: [String: String]

    var id: String { appID }

    /// 按系统语言取展示名。
    var localizedName: String {
        OurAppsProvider.localizedName(from: names)
    }
}

// MARK: - 数据加载与跳转

enum OurAppsProvider {
    /// 启动时一次性解析，避免重复读盘。
    static let apps: [OurAppItem] = Self.load()

    private static func load() -> [OurAppItem] {
        guard let url = Bundle.main.url(forResource: "OurApps", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let rawApps = root["apps"] as? [[String: Any]] else {
            return []
        }
        return rawApps.compactMap { dict -> OurAppItem? in
            guard let appID = dict["appID"] as? String,
                  let imageName = dict["imageName"] as? String,
                  let names = dict["names"] as? [String: String] else {
                return nil
            }
            return OurAppItem(appID: appID, imageName: imageName, names: names)
        }
    }

    /// 依据系统语言偏好选取名称：精确(含地区) → 基类(zh-Hans→zh) → 反向基类匹配 → 回退英文。
    static func localizedName(from names: [String: String]) -> String {
        let preferred = Locale.preferredLanguages
        for lang in preferred where names[lang] != nil { return names[lang]! }
        for lang in preferred {
            let base = String(lang.split(separator: "-").first ?? "")
            if let name = names[base] { return name }
        }
        for lang in preferred {
            let base = String(lang.split(separator: "-").first ?? "")
            for (key, value) in names where key.hasPrefix(base) { return value }
        }
        return names["en"] ?? names.values.first ?? ""
    }

    /// 打开该应用在 App Store 的页面。
    @MainActor
    static func openStore(_ appID: String) {
        let urlString = "https://apps.apple.com/app/id\(appID)"
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url, options: [:])
    }
}

// MARK: - 设置页模块

/// 「我们的应用」的行内容（不含 Section 外壳），用于和「关于」合并进同一组。
/// 图标与标题由调用方的模块图标行统一提供，这里只负责可点击的应用列表。
struct OurAppsRows: View {
    private let apps = OurAppsProvider.apps

    var body: some View {
        ForEach(apps) { app in
            Button {
                OurAppsProvider.openStore(app.appID)
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    Image(app.imageName)
                        .resizable()
                        .scaledToFill()
                        // 与设置页 3D 配置图标同宽，应用名与标题行文字左边缘对齐。
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(app.localizedName)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Text.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Text.secondary.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
        }
    }
}
