import Foundation
import UIKit

/// 範囲を指定して、地理院タイルをまとめて保存する係。
///
/// 量と速さの上限は `OfflineMapPolicy` にあります。ここでは必ずその上限に従います。
@MainActor
final class OfflineMapDownloader: ObservableObject {
    /// アプリ全体で1つ。予定の画面から保存を始めて、別のタブへ移っても続くようにするためです。
    /// 画面ごとに持たせると、画面を閉じた拍子に進み具合が見えなくなります。
    static let shared = OfflineMapDownloader()

    @Published private(set) var isRunning = false
    /// いま取っている範囲。一覧で「保存しています…」と出し分けるのに使います。
    @Published private(set) var currentAreaID: UUID?
    @Published private(set) var finishedCount = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var failedCount = 0

    /// 進み具合（0〜100）。
    ///
    /// 画面には枚数ではなくこちらを出す。「47 / 369 枚」では、利用者には何の枚数か分からないため。
    var percent: Int {
        guard totalCount > 0 else { return 0 }
        return min(100, finishedCount * 100 / totalCount)
    }

    private let store: OfflineTileStore
    private var task: Task<Void, Never>?

    /// まとめて保存するときは、画面を見ているときの読み込みとは別の通信を使う。
    /// 待つ上限を少し長めにして、電波の良い場所で落ち着いて取り切るためです。
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.httpMaximumConnectionsPerHost = OfflineMapPolicy.concurrentRequests
        return URLSession(configuration: configuration)
    }()

    init(store: OfflineTileStore = .shared) {
        self.store = store
    }

    /// 範囲のタイルを取りに行く。保存済みのものは飛ばします。
    /// 終わったら、保存できた枚数・大きさ・最後まで取れたかを範囲に書き込みます。
    func start(_ area: OfflineArea, onFinish: @escaping () -> Void = {}) {
        guard !isRunning else { return }
        let keys = area.keys
        guard keys.count <= OfflineMapPolicy.maximumTilesPerArea else { return }

        isRunning = true
        currentAreaID = area.id
        finishedCount = 0
        failedCount = 0
        totalCount = keys.count
        // 取っている間に画面が消えると通信が止まるため、取り終えるまで画面を点けておく。
        UIApplication.shared.isIdleTimerDisabled = true

        task = Task { [store] in
            let saved = await run(keys)
            area.savedTileCount = saved
            area.isComplete = !Task.isCancelled
            area.byteCount = Self.bytes(of: keys, in: store)
            try? area.modelContext?.save()
            UIApplication.shared.isIdleTimerDisabled = false
            isRunning = false
            currentAreaID = nil
            onFinish()
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// 範囲のタイルの合計の大きさ。
    nonisolated static func bytes(of keys: [TileKey], in store: OfflineTileStore) -> Int64 {
        keys.reduce(Int64(0)) { total, key in
            let size = (try? store.url(for: key).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    /// 決まった数の取り手で順に取る。戻り値は保存済みの枚数（もともとあったものを含む）。
    private func run(_ keys: [TileKey]) async -> Int {
        var queue = keys[...]
        var saved = 0

        await withTaskGroup(of: Bool.self) { group in
            func addNext() {
                guard let key = queue.popFirst() else { return }
                group.addTask { [store] in
                    await Self.fetch(key, into: store)
                }
            }
            for _ in 0..<OfflineMapPolicy.concurrentRequests { addNext() }

            for await ok in group {
                finishedCount += 1
                if ok { saved += 1 } else { failedCount += 1 }
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                addNext()
            }
        }
        return saved
    }

    /// 1枚取って保存する。保存済みなら取りに行かない。
    nonisolated private static func fetch(_ key: TileKey, into store: OfflineTileStore) async -> Bool {
        if store.contains(key) { return true }
        guard let url = key.tile.url(z: key.z, x: key.x, y: key.y) else { return false }

        // 取りに行く間隔を空ける。サーバーへの負荷を抑えるためです。
        try? await Task.sleep(for: .seconds(OfflineMapPolicy.intervalBetweenRequests))
        guard !Task.isCancelled,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            // 海の上など、配信が無いところは 404 が返る。失敗として数えるだけで止めない。
            return false
        }
        return (try? store.save(data, for: key)) != nil
    }
}
