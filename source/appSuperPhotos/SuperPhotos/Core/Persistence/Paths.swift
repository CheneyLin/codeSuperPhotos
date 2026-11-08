import Foundation

/// 沙盒路径管理。
/// 容器路径在重装/迁移后会变化，因此清单里只允许存相对 Application Support 的路径。
enum Paths {
    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
    }

    static var vaultDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Vault", isDirectory: true)
    }

    @discardableResult
    static func ensureVaultDirectory() -> URL {
        let directory = vaultDirectory
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func vaultFileURL(relativePath: String) -> URL {
        applicationSupportDirectory.appendingPathComponent(relativePath)
    }

    /// 生成 `Vault/<uuid>.<ext>` 形式的相对路径。
    static func makeRelativePath(fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension
        let name = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext.lowercased())")
        return "Vault/\(name)"
    }

    static func fileSize(atRelativePath relativePath: String) -> Int64 {
        let url = vaultFileURL(relativePath: relativePath)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func fileExists(atRelativePath relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: vaultFileURL(relativePath: relativePath).path)
    }

    static func removeFile(atRelativePath relativePath: String) {
        guard !relativePath.isEmpty else { return }
        try? FileManager.default.removeItem(at: vaultFileURL(relativePath: relativePath))
    }

    /// 写入后设置文件保护并排除 iCloud 备份。
    static func applyVaultFileAttributes(to url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    static func applyVaultDirectoryAttributes() {
        let directory = ensureVaultDirectory()
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = directory
        try? mutableURL.setResourceValues(values)
    }

    /// 剩余可用于重要用途的空间。
    static func availableCapacity() -> Int64 {
        let values = try? applicationSupportDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
