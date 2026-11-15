import MapKit
import SwiftData
import SwiftUI

/// 登山計画の作成・編集。入力するそばから出発時刻の逆算が更新されます。
struct PlanEditorView: View {
    @Bindable var plan: HikePlan

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationProvider = CurrentLocationProvider()

    @State private var weather: [DailyWeather] = []
    @State private var weatherError: String?
    @State private var isLoadingWeather = false

    @State private var isPickingParking = false
    @State private var isSearchingOrigin = false
    @State private var isEditingCourseTime = false
    @State private var isPickingRoute = false
    @State private var isEditingToll = false

    @State private var routeError: String?
    @State private var isCalculatingRoute = false

    var body: some View {
        Form {
            summarySection
            dateSection
            trailheadSection
            originSection
            courseTimeSection
            PlanScheduleSection(plan: plan)
            PlanWeatherSection(
                forecast: weather,
                date: plan.date,
                isLoading: isLoadingWeather,
                errorMessage: weatherError
            )
            driveSection
        }
        .navigationTitle(plan.mountainName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPickingParking) {
            ParkingPickerView(summit: plan.summitCoordinate) { spot in
                applyTrailhead(name: spot.name, coordinate: spot.coordinate)
            }
        }
        .sheet(isPresented: $isPickingRoute) {
            RoutePickerView(routes: availableRoutes) { route in
                plan.apply(route: route)
            }
        }
        .sheet(isPresented: $isSearchingOrigin) {
            PlaceSearchView(center: plan.summitCoordinate) { name, coordinate in
                plan.originName = name
                plan.originLatitude = coordinate.latitude
                plan.originLongitude = coordinate.longitude
                Task { await calculateRoute() }
            }
        }
        // 日付か山が変われば天気を取り直す。
        .task(id: "\(plan.date.timeIntervalSince1970)-\(plan.mountainID)") {
            await loadWeather()
        }
    }

    // MARK: - 山の概要

    private var summarySection: some View {
        Section {
            LabeledContent("山頂の標高", value: "\(Int(plan.summitElevation)) m")
            if let gain = plan.elevationGain {
                LabeledContent("登山口からの標高差", value: "\(Int(gain)) m")
            }
        }
    }

    // MARK: - 日付

    private var dateSection: some View {
        Section("登る日") {
            DatePicker("日付", selection: $plan.date, displayedComponents: .date)
                .datePickerStyle(.compact)
        }
    }

    // MARK: - 登山口

    private var trailheadSection: some View {
        Section {
            Button {
                isPickingParking = true
            } label: {
                if let name = plan.trailheadName {
                    LabeledContent("登山口（駐車場）", value: name)
                } else {
                    Label("駐車場から登山口を選ぶ", systemImage: "parkingsign.circle")
                }
            }

            if let elevation = plan.trailheadElevation {
                LabeledContent("登山口の標高", value: "\(Int(elevation)) m")
            }

            if plan.trailheadName != nil {
                TextField(
                    "駐車場のメモ（料金・台数など）",
                    text: Binding(
                        get: { plan.parkingNote ?? "" },
                        set: { plan.parkingNote = $0.isEmpty ? nil : $0 }
                    ),
                    axis: .vertical
                )
                .lineLimit(2...4)
            }
        } header: {
            Text("登山口")
        } footer: {
            if plan.trailheadName != nil {
                Text("駐車場の料金と台数は、地図サービスからは取得できません。調べた内容をメモに残しておくと次回以降に役立ちます。")
            }
        }
    }

    // MARK: - 出発地

    private var originSection: some View {
        Section("出発地") {
            Button {
                Task { await useCurrentLocation() }
            } label: {
                HStack {
                    Label("現在地を使う", systemImage: "location.fill")
                    Spacer()
                    if locationProvider.isLocating {
                        ProgressView()
                    }
                }
            }

            Button {
                isSearchingOrigin = true
            } label: {
                Label("住所・地名で探す", systemImage: "magnifyingglass")
            }

            if let name = plan.originName {
                LabeledContent("設定中", value: name)
            }

            if let message = locationProvider.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - コースタイム

    /// この山について調査済みのルート。
    private var availableRoutes: [CourseRoute] {
        CourseRouteData.routes(for: plan.mountainID)
    }

    private var courseTimeSection: some View {
        Section {
            if !availableRoutes.isEmpty {
                Button {
                    isPickingRoute = true
                } label: {
                    LabeledContent(
                        "登山ルート",
                        value: plan.routeName ?? "選ぶ（\(availableRoutes.count)件）"
                    )
                }
                if let startName = plan.routeStartName {
                    LabeledContent("ルートの登山口", value: startName)
                        .font(.caption)
                }
                if let grade = plan.routeGradeText {
                    LabeledContent("グレード", value: grade)
                        .font(.caption)
                }
                if plan.routeIsRoundTrip == false {
                    Label("往復ではないルートです。車の回収方法を確認してください。",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Button {
                isEditingCourseTime = true
            } label: {
                LabeledContent(
                    "標準コースタイム（往復）",
                    value: plan.courseTimeSeconds > 0
                        ? TrackStatistics.hourMinuteText(plan.courseTimeSeconds)
                        : "未設定"
                )
            }
            .alert("標準コースタイム", isPresented: $isEditingCourseTime) {
                courseTimeInput
            } message: {
                Text("ガイドブックや登山地図に載っている往復の時間を、分単位で入力してください。")
            }

            Picker("ペース", selection: $plan.pace) {
                ForEach(HikePace.allCases) { pace in
                    Text("\(pace.label)（\(pace.detail)）").tag(pace)
                }
            }

            if plan.courseTimeSeconds > 0 {
                LabeledContent(
                    "あなたのペースでの行動時間",
                    value: TrackStatistics.hourMinuteText(plan.courseTimeSeconds * plan.pace.rawValue)
                )
                .fontWeight(.medium)
            }
        } header: {
            Text("行動時間")
        } footer: {
            Text(courseTimeFooter)
        }
    }

    private var courseTimeFooter: String {
        guard plan.courseTimeSeconds > 0 else {
            return "登山口を選ぶと、標高差からおおよその時間を自動で入れます。"
        }
        if plan.courseTimeSource.needsCaution {
            return "⚠️ \(plan.courseTimeSource.label)です。標高差だけで計算しており水平距離を考慮していないため、"
                + "なだらかに長く歩く山では短く出ます。"
                + (availableRoutes.isEmpty
                   ? "ガイドブックの値が分かるなら上書きしてください。"
                   : "上の登山ルートから選ぶと、公表されている標準コースタイムを使えます。")
        }
        if plan.courseTimeSource == .researched {
            return "出典: 十県一山域の日本百名山「登山ルートグレーディング」一覧表（各県公表）。"
        }
        return plan.courseTimeSource.label + "を使っています。"
    }

    @ViewBuilder
    private var courseTimeInput: some View {
        TextField(
            "分",
            value: Binding(
                get: { Int(plan.courseTimeSeconds / 60) },
                set: {
                    plan.courseTimeSeconds = TimeInterval($0 * 60)
                    plan.courseTimeSource = .manual
                }
            ),
            format: .number
        )
        .keyboardType(.numberPad)
        Button("OK") {}
        Button("キャンセル", role: .cancel) {}
    }

    // MARK: - 移動

    @ViewBuilder
    private var driveSection: some View {
        Section {
            if isCalculatingRoute {
                HStack { ProgressView(); Text("経路を計算中…").foregroundStyle(.secondary) }
            } else if let seconds = plan.driveTimeSeconds {
                LabeledContent("移動時間", value: TrackStatistics.hourMinuteText(seconds))
                if let distance = plan.driveDistance {
                    LabeledContent("距離", value: String(format: "%.1f km", distance / 1000))
                }
                if let names = plan.highwayNamesText, !names.isEmpty {
                    LabeledContent("通る高速道路", value: names)
                }
                if let toll = plan.tollEstimate {
                    Button {
                        isEditingToll = true
                    } label: {
                        LabeledContent(
                            toll.isManual ? "高速料金" : "高速料金（概算）",
                            value: toll.amountText
                        )
                    }
                    .alert("高速料金", isPresented: $isEditingToll) { tollInput } message: {
                        Text("ドラぷら等で調べた金額を円単位で入力すると、概算を上書きできます。")
                    }
                }
                Link(destination: TollEstimate.driveplazaURL) {
                    Label("ドラぷらで正確な料金を調べる", systemImage: "arrow.up.right.square")
                }
            } else if let routeError {
                Text(routeError).font(.callout).foregroundStyle(.secondary)
            } else {
                Text("出発地と登山口を設定すると計算します。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("移動（自家用車）")
        } footer: {
            if plan.tollEstimate?.isManual == false {
                Text("高速料金は普通車の対距離料金（24.6円/km＋150円）からの概算です。"
                     + "NEXCO は料金を取得できる公開APIを提供していないため、"
                     + "深夜割引・休日割引・大都市近郊区間の割増は反映されません。")
            }
        }
    }

    @ViewBuilder
    private var tollInput: some View {
        TextField(
            "円",
            value: Binding(
                get: { plan.tollAmountOverride ?? plan.tollEstimate?.amount ?? 0 },
                set: { plan.tollAmountOverride = $0 }
            ),
            format: .number
        )
        .keyboardType(.numberPad)
        Button("OK") {}
        Button("概算に戻す", role: .destructive) { plan.tollAmountOverride = nil }
        Button("キャンセル", role: .cancel) {}
    }

    // MARK: - 処理

    private func applyTrailhead(name: String, coordinate: CLLocationCoordinate2D) {
        plan.trailheadName = name
        plan.trailheadLatitude = coordinate.latitude
        plan.trailheadLongitude = coordinate.longitude

        Task {
            // 登山口の標高を取って、標高差からコースタイムの初期値を入れる。
            if let elevation = try? await ElevationService.elevation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ) {
                plan.trailheadElevation = elevation
                // 手で入れた値や調べた値は尊重し、概算のときだけ入れ替える。
                if plan.courseTimeSource == .estimated || plan.courseTimeSeconds == 0 {
                    let gain = max(0, plan.summitElevation - elevation)
                    plan.courseTimeSeconds = HikePlanner.estimatedCourseTime(elevationGain: gain)
                    plan.courseTimeSource = .estimated
                }
            }
            await calculateRoute()
        }
    }

    private func useCurrentLocation() async {
        guard let location = try? await locationProvider.current() else { return }
        plan.originName = "現在地"
        plan.originLatitude = location.coordinate.latitude
        plan.originLongitude = location.coordinate.longitude
        await calculateRoute()
    }

    private func calculateRoute() async {
        guard let origin = plan.originCoordinate,
              let trailhead = plan.trailheadCoordinate else { return }

        isCalculatingRoute = true
        routeError = nil
        defer { isCalculatingRoute = false }

        do {
            let estimate = try await RouteService.drive(from: origin, to: trailhead)
            plan.driveTimeSeconds = estimate.travelTime
            plan.driveDistance = estimate.distance
            plan.estimatedHighwayDistance = estimate.estimatedHighwayDistance
            plan.highwayNamesText = estimate.highwayNames.joined(separator: "・")
        } catch {
            routeError = error.localizedDescription
        }
    }

    private func loadWeather() async {
        isLoadingWeather = true
        weatherError = nil
        defer { isLoadingWeather = false }

        do {
            weather = try await WeatherService.forecast(
                latitude: plan.summitLatitude,
                longitude: plan.summitLongitude
            )
        } catch {
            weatherError = error.localizedDescription
        }
    }
}
