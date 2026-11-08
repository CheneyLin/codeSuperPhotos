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
        guard let createdAt else { return "未知日期" }
        return Self.dateFormatter.string(from: createdAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()
}

/// 查询范围：媒体类型 + 相簿。
struct LibraryFilter: Equatable, Sendable {
    var mediaKind: MediaKind?
    var albumLocalID: String?
    var albumTitle: String

    static let all = LibraryFilter(mediaKind: nil, albumLocalID: nil, albumTitle: "全部照片")

    var title: String {
        if let mediaKind {
            return "\(albumTitle) · \(mediaKind.displayName)"
        }
        return albumTitle
    }
}
