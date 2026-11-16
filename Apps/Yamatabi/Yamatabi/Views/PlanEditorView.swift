import MapKit
import SwiftData
import SwiftUI

/// 登山計画の作成・編集。入力するそばから出発時刻の逆算が更新されます。
struct PlanEditorView: View {
    @Bindable var plan: HikePlan

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationProvider = CurrentLocationProvider()
    @ObservedObject private var settings = UserSettings.shared

    @State private var weather: [DailyWeather] = []
    @State private var weatherError: String?
    @State private var isLoadingWeather = false

    @State private var isPickingParking = false
    @State private var isSearchingOrigin = false
    // 計画画面の表示系は、すべてここ（Form 直下）にまとめる。
    // Section に付けると Form が行ごとに配ってしまい、同じフラグの画面が
    // 同時に複数立ち上がって navigation が壊れる。
    @State private var isPickingRoute = false
    @State private var isEditingCourseTime = false
    @State private var isEditingToll = false

    @State private var routeError: String?
    @State private var isCalculatingRoute = false

    var body: some View {
        Form {
            summarySection
            dateSection
            trailheadSection
            originSection
            PlanCourseTimeSection(
                plan: plan,
                availableRoutes: availableRoutes,
                onPickRoute: { isPickingRoute = true },
                onEditCourseTime: { isEditingCourseTime = true }
            )
            PlanScheduleSection(plan: plan)
            PlanWeatherSection(
                forecast: weather,
                date: plan.date,
                isLoading: isLoadingWeather,
                errorMessage: weatherError
            )
            PlanDriveSection(
                plan: plan,
                isCalculating: isCalculatingRoute,
                errorMessage: routeError,
                onEditToll: { isEditingToll = true }
            )
        }
        .navigationTitle(plan.mountainName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPickingRoute) {
            RoutePickerView(routes: availableRoutes) { route in
                plan.apply(route: route)
            }
        }
        .alert("標準コースタイム", isPresented: $isEditingCourseTime) {
            PlanCourseTimeInput(plan: plan)
        } message: {
            Text("ガイドブックや登山地図に載っている往復の時間を、分単位で入力してください。")
        }
        .alert("高速料金", isPresented: $isEditingToll) {
            PlanTollInput(plan: plan, vehicle: settings.vehicleClass)
        } message: {
            Text("ドラぷら等で調べた金額を円単位で入力すると、概算を上書きできます。")
        }
        .sheet(isPresented: $isPickingParking) {
            ParkingPickerView(summit: plan.summitCoordinate) { spot in
                applyTrailhead(name: spot.name, coordinate: spot.coordinate)
            }
        }
        .sheet(isPresented: $isSearchingOrigin) {
            PlaceSearchView(
                center: plan.summitCoordinate,
                initialQuery: settings.homeName ?? ""
            ) { name, coordinate in
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
        Section {
            if let homeName = settings.homeName, let home = settings.homeCoordinate {
                Button {
                    plan.originName = homeName
                    plan.originLatitude = home.latitude
                    plan.originLongitude = home.longitude
                    Task { await calculateRoute() }
                } label: {
                    Label("自宅から（\(homeName)）", systemImage: "house.fill")
                }
            }

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

            // 出発地が決まっていて、まだ自宅を登録していないなら、ここで登録できるようにする。
            if let name = plan.originName,
               let coordinate = plan.originCoordinate,
               !settings.hasHome {
                Button {
                    settings.setHome(name: name, coordinate: coordinate)
                } label: {
                    Label("この出発地を自宅として登録", systemImage: "house.badge.plus")
                }
            }
        } header: {
            Text("出発地")
        }
    }

    // MARK: - コースタイム

    // MARK: - 入力欄

    /// この山について調査済みのルート。
    private var availableRoutes: [CourseRoute] {
        CourseRouteData.routes(for: plan.mountainID)
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
