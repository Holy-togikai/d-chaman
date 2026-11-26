import SwiftData
import SwiftUI

/// アプリの一番外側。ホーム・地図・記録の3つに分けています。
///
/// `LocationTracker` をここで持つのが肝心なところです。地図の画面の中に持たせると、
/// タブを移った拍子に記録が止まってしまいます。root に置けば、どのタブを見ていても
/// 記録は動き続けます。
struct RootView: View {
    @StateObject private var tracker = LocationTracker()
    @State private var tab: Tab = .home
    /// オフライン地図タブから、保存した範囲を地図タブで見せるときに使う。
    @State private var mapFocus: MapFocus?

    enum Tab {
        case home
        case map
        case records
        case offline
    }

    var body: some View {
        TabView(selection: $tab) {
            HomeView(tracker: tracker, onOpenMap: { tab = .map })
                .tabItem { Label("ホーム", systemImage: "house") }
                .tag(Tab.home)

            MapTabView(tracker: tracker, onPlanCreated: { tab = .home }, focusedBox: mapFocus)
                .tabItem { Label("地図", systemImage: "map") }
                .tag(Tab.map)

            RecordListView(showsCloseButton: false)
                .tabItem { Label("記録", systemImage: "list.bullet.rectangle") }
                .tag(Tab.records)

            // 保存した地図は容量を食うので、いつでも中身を見て消せるようタブに置く。
            OfflineMapsView(onShow: { box in
                mapFocus = MapFocus(box: box)
                tab = .map
            })
            .tabItem { Label("オフライン地図", systemImage: "arrow.down.circle") }
            .tag(Tab.offline)
        }
        .tint(.brandGreen)
    }
}

#Preview {
    RootView()
        .modelContainer(for: [HikeRecord.self, HikePlan.self], inMemory: true)
}
