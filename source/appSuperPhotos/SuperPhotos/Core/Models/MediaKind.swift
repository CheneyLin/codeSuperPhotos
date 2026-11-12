import Foundation

/// 照片的媒体类型。免费版保险箱只接受静态图片。
enum MediaKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case photo
    case video
    case livePhoto
    case screenshot
    case panorama
    case animated

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .photo: "照片".localized
        case .video: "视频".localized
        case .livePhoto: "实况照片".localized
        case .screenshot: "截图".localized
        case .panorama: "全景".localized
        case .animated: "动图".localized
        }
    }

    /// 静态图片：免费版可用。实况照片与视频需要 VIP。
    var isStillImage: Bool {
        switch self {
        case .photo, .screenshot, .panorama, .animated: true
        case .livePhoto, .video: false
        }
    }
}
