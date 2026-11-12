import Foundation
import CoreGraphics

/// 运行时照片条目；不持久化 PHAsset，仅保留界面需要的元数据。
struct PhotoItem: Identifiable, Hashable, Sendable {
    let id: String
    let kind: MediaKind
    let pixelSize: CGSize
    let duration: TimeInterval
    let createdAt: Date?
    let isHidden: Bool

    var aspectRatio: CGFloat {
        pixelSize.height > 0 ? pixelSize.width / pixelSize.height : 1
    }

    var isVideo: Bool { kind == .video }

    /// 舞台页码等处的短日期文案
    var shortDateText: String {
        guard let createdAt else { return "未知日期".localized }
        return Self.dateFormatter.string(from: createdAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // 跟随当前语言：简中显示「2026年11月12日」，英文显示「Nov 12, 2026」。
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("yMd")
        return formatter
    }()
}

/// 查询范围：只按相簿筛选，媒体类型不再参与取数。
struct LibraryFilter: Equatable, Sendable {
    var albumLocalID: String?
    var albumTitle: String

    static let all = LibraryFilter(albumLocalID: nil, albumTitle: "全部照片".localized)

    var title: String { albumTitle }
}
