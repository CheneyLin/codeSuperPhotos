import Foundation
import SwiftData

/// 保险箱清单。只存业务需要的最小元数据，文件路径一律相对 Application Support。
@Model
final class VaultRecord {
    @Attribute(.unique) var id: UUID
    /// 入库时的系统资产 id，用于从舞台排除；原件删除后可能失效。
    var originLocalID: String?
    var fileName: String
    var mediaKindRaw: String
    var byteSize: Int64
    var capturedAt: Date?
    var addedAt: Date
    var albumNames: [String]
    var relativePath: String
    /// Live Photo 的成对视频（相对路径）。
    var pairedVideoPath: String?
    /// active / broken
    var stateRaw: String
    /// 副本已写入但原件删除失败（用户取消或系统错误）。
    var pendingRemoval: Bool

    init(
        id: UUID = UUID(),
        originLocalID: String?,
        fileName: String,
        mediaKind: MediaKind,
        byteSize: Int64,
        capturedAt: Date?,
        addedAt: Date = Date(),
        albumNames: [String] = [],
        relativePath: String,
        pairedVideoPath: String? = nil,
        state: VaultRecordState = .active,
        pendingRemoval: Bool = false
    ) {
        self.id = id
        self.originLocalID = originLocalID
        self.fileName = fileName
        self.mediaKindRaw = mediaKind.rawValue
        self.byteSize = byteSize
        self.capturedAt = capturedAt
        self.addedAt = addedAt
        self.albumNames = albumNames
        self.relativePath = relativePath
        self.pairedVideoPath = pairedVideoPath
        self.stateRaw = state.rawValue
        self.pendingRemoval = pendingRemoval
    }

    var mediaKind: MediaKind {
        MediaKind(rawValue: mediaKindRaw) ?? .photo
    }

    var state: VaultRecordState {
        get { VaultRecordState(rawValue: stateRaw) ?? .active }
        set { stateRaw = newValue.rawValue }
    }

    var displayDateText: String {
        guard let capturedAt else { return "未知日期" }
        return Self.dateFormatter.string(from: capturedAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()
}

enum VaultRecordState: String, Codable, Sendable {
    case active
    /// 文件缺失或读取失败，等待用户处理。
    case broken
}
