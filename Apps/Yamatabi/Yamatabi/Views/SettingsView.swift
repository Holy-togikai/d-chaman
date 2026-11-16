import CoreLocation
import SwiftUI

/// 計画をまたいで使う設定。自宅と車種を決めておくと、毎回の入力が減ります。
struct SettingsView: View {
    @ObservedObject private var settings = UserSettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isSearchingHome = false

    var body: some View {
        NavigationStack {
            Form {
                homeSection
                vehicleSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $isSearchingHome) {
                PlaceSearchView(
                    center: .init(latitude: 35.0, longitude: 137.0),
                    initialQuery: settings.homeName ?? "",
                    title: "自宅を探す"
                ) { name, coordinate in
                    settings.setHome(name: name, coordinate: coordinate)
                }
            }
        }
    }

    private var homeSection: some View {
        Section {
            Button {
                isSearchingHome = true
            } label: {
                if let name = settings.homeName {
                    LabeledContent("自宅", value: name)
                } else {
                    Label("自宅を登録する", systemImage: "house")
                }
            }

            if settings.hasHome {
                Button("登録を消す", role: .destructive) {
                    settings.clearHome()
                }
            }
        } header: {
            Text("自宅")
        } footer: {
            Text("登録しておくと、計画の出発地としてすぐに使えます。"
                 + "番地まで入れる必要はありません。最寄りの駅や目印でも、移動時間の見積もりには十分です。")
        }
    }

    private var vehicleSection: some View {
        Section {
            Picker("車種", selection: $settings.vehicleClass) {
                ForEach(VehicleClass.allCases) { vehicle in
                    Text(vehicle.label).tag(vehicle)
                }
            }
        } header: {
            Text("車")
        } footer: {
            Text("高速料金の概算に使います。普通車を基準に、軽自動車は約0.8倍、"
                 + "中型車は約1.2倍として計算します。割引は反映されません。")
        }
    }
}
