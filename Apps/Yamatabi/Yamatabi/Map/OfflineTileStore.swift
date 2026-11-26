import Foundation

/// 保存した地理院タイルの置き場所。
///
/// 国土地理院の回答（決定記録 0001）で、保存が申請不要なのは「利用者の私的利用」に
/// 留まる場合だけです。そのため、ここに置いたタイルは**この端末の中で表示するためだけ**に
/// 使います。書き出す・共有する・加工して保存する口は作らないでください。
///
/// iCloud のバックアップからも外しています。容量が大きいうえ、いつでも取り直せるためです。
struct OfflineTileStore {
    let root: URL

    static let shared = OfflineTileStore(
        root: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineTiles", isDirectory: true)
    )

    func url(for key: TileKey) -> URL {
        root
            .appendingPathComponent(key.tile.rawValue, isDirectory: true)
            .appendingPathComponent(String(key.z), isDirectory: true)
            .appendingPathComponent(String(key.x), isDirectory: true)
            .appendingPathComponent("\(key.y).\(key.tile.fileExtension)")
    }

    func contains(_ key: TileKey) -> Bool {
        FileManager.default.fileExists(atPath: url(for: key).path)
    }

    func data(for key: TileKey) -> Data? {
        try? Data(contentsOf: url(for: key))
    }

    func save(_ data: Data, for key: TileKey) throws {
        let file = url(for: key)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: file, options: .atomic)
        excludeRootFromBackup()
    }

    func remove(_ key: TileKey) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    /// 保存しているタイルの合計の大きさ（バイト）。
    func totalBytes() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    private func excludeRootFromBackup() {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var root = root
        try? root.setResourceValues(values)
    }
}
