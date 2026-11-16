import SwiftData
import SwiftUI

/// アプリの入口。`@main` が付いた構造体が1つだけ必要で、ここからアプリが始まります。
@main
struct YamatabiApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        // 登山記録と登山計画の保存先。端末内のデータベースに永続化されます。
        .modelContainer(for: [HikeRecord.self, HikePlan.self])
    }
}
