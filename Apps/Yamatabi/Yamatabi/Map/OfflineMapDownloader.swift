import Foundation
import UIKit

/// 範囲を指定して、地理院タイルをまとめて保存する係。
///
/// 量と速さの上限は `OfflineMapPolicy` にあります。ここでは必ずその上限に従います。
@MainActor
final class OfflineMapDownloader: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var finishedCount = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var failedCount = 0

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

    /// 範囲のタイルを取りに行く。保存済みのものは飛ばします。終わったら `onFinish` を呼びます。
    func start(_ area: OfflineArea, onFinish: @escaping (_ saved: Int, _ completed: Bool) -> Void) {
        guard !isRunning else { return }
        let keys = area.keys
        guard keys.count <= OfflineMapPolicy.maximumTilesPerArea else { return }

        isRunning = true
        finishedCount = 0
        failedCount = 0
        totalCount = keys.count
        // 取っている間に画面が消えると通信が止まるため、取り終えるまで画面を点けておく。
        UIApplication.shared.isIdleTimerDisabled = true

        task = Task {
            let saved = await run(keys)
            let completed = !Task.isCancelled
            UIApplication.shared.isIdleTimerDisabled = false
            isRunning = false
            onFinish(saved, completed)
        }
    }

    func cancel() {
        task?.cancel()
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
