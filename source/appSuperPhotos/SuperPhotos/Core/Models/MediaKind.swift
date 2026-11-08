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
        case .photo: "照片"
        case .video: "视频"
        case .livePhoto: "实况照片"
        case .screenshot: "截图"
        case .panorama: "全景"
        case .animated: "动图"
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
