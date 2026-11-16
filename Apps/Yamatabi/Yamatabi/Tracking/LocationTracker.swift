import CoreLocation
import Foundation

/// 登山中の現在地を追い続け、軌跡と統計を提供する。
///
/// 登山は行動時間が長いため、電池持ちが品質に直結します。設定の意図は各所のコメントを参照。
final class LocationTracker: NSObject, ObservableObject {

    enum State: Equatable {
        case idle
        case recording
        case paused
    }

    /// 記録を始められない理由。
    enum Problem: Equatable {
        case permissionDenied
    }

    @Published private(set) var state: State = .idle
    /// 記録中の軌跡。
    @Published private(set) var points: [TrackPoint] = []
    /// 記録中の統計（1秒ごとに更新）。
    @Published private(set) var statistics: TrackStatistics = .zero
    /// 最後に受け取った測位結果。記録していなくても現在地表示に使えます。
    @Published private(set) var latest: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var problem: Problem?

    /// 記録対象の山。開始時に指定します。
    private(set) var mountainName: String?
    /// 記録対象の山の地理院ID。あとから山を引き直すために残します。
    private(set) var mountainID: String?
    private(set) var startedAt: Date?

    private let manager = CLLocationManager()
    private var ticker: Timer?

    /// 一時停止していた時間の合計。経過時間から差し引きます。
    private var pausedTotal: TimeInterval = 0
    private var pausedAt: Date?
    /// 権限ダイアログの応答を待ってから記録を始めるためのフラグ。
    private var startWhenAuthorized = false

    override init() {
        super.init()
        manager.delegate = self

        // 登山向けの測位設定。
        //
        // ・Best で十分。BestForNavigation は車載ナビ向けで、常時フル稼働して電池を激しく消費する。
        // ・distanceFilter は「何メートル動いたら通知するか」。5m なら登山道の形状は十分に拾えて、
        //   立ち止まっている間は通知が来ないので省電力になる。
        // ・activityType = .fitness で、OS に徒歩での利用だと伝える。
        // ・pausesLocationUpdatesAutomatically は必ず false。
        //   true のままだと iOS が「動いていない」と判断して勝手に測位を止めてしまい、
        //   休憩後に記録が再開されない事故が起きる。登山アプリでは致命的。
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false

        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - 操作

    /// 記録を開始する。権限が未確認なら、先に許可を求めます。
    func start(mountainName: String?, mountainID: String?) {
        self.mountainName = mountainName
        self.mountainID = mountainID
        problem = nil

        switch authorizationStatus {
        case .notDetermined:
            // 「App の使用中のみ許可」を求める。登山アプリに「常に許可」は不要で、
            // バックグラウンド位置更新と併用すれば画面を消していても記録し続けられる。
            startWhenAuthorized = true
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            problem = .permissionDenied
        case .authorizedWhenInUse, .authorizedAlways:
            beginUpdates()
        @unknown default:
            problem = .permissionDenied
        }
    }

    /// 一時停止。測位は止めるが、それまでの軌跡は保持します。
    func pause() {
        guard state == .recording else { return }
        manager.stopUpdatingLocation()
        pausedAt = Date()
        state = .paused
        stopTicker()
    }

    func resume() {
        guard state == .paused else { return }
        if let pausedAt {
            pausedTotal += Date().timeIntervalSince(pausedAt)
        }
        pausedAt = nil
        manager.startUpdatingLocation()
        state = .recording
        startTicker()
    }

    /// 記録を終えたときに取り出せる、保存用のひとまとまり。
    struct Result {
        let points: [TrackPoint]
        let statistics: TrackStatistics
        let startedAt: Date
        let mountainName: String?
        let mountainID: String?
    }

    /// 記録を終了し、保存用のデータを返す。返り値が nil なら、保存に値する軌跡がなかった場合。
    @discardableResult
    func finish() -> Result? {
        guard state != .idle else { return nil }

        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        stopTicker()

        defer { reset() }

        guard points.count >= 2, let startedAt else { return nil }

        var finalStats = TrackMath.statistics(for: points)
        finalStats.elapsed = currentElapsed
        return Result(
            points: points,
            statistics: finalStats,
            startedAt: startedAt,
            mountainName: mountainName,
            mountainID: mountainID
        )
    }

    /// 記録を破棄する。
    func discard() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        stopTicker()
        reset()
    }

    // MARK: - 内部

    private func beginUpdates() {
        // 位置情報サービス自体の ON/OFF は、ここでは確認しない。
        // CLLocationManager.locationServicesEnabled() はメインスレッドを
        // 長時間ブロックしうると Apple が明示しているため、呼ばない方針。
        // 実際に使えない場合は測位が届かないだけで、権限の問題は
        // locationManagerDidChangeAuthorization で捕まえられる。

        // 画面を消していても記録を続けるために必要。
        // Info.plist の UIBackgroundModes に location が無い状態でこれを true にすると
        // アプリがクラッシュするため、ビルド設定とセットで管理すること。
        manager.allowsBackgroundLocationUpdates = true
        // 記録中であることを示す青いインジケータを出す。隠して測位し続けるのは不誠実。
        manager.showsBackgroundLocationIndicator = true

        points = []
        statistics = .zero
        pausedTotal = 0
        pausedAt = nil
        startedAt = Date()
        state = .recording

        manager.startUpdatingLocation()
        startTicker()
    }

    private func reset() {
        state = .idle
        points = []
        statistics = .zero
        startedAt = nil
        mountainName = nil
        mountainID = nil
        pausedTotal = 0
        pausedAt = nil
        startWhenAuthorized = false
    }

    /// 休憩を除いた経過時間。表示を1秒ごとに進めるため、軌跡ではなく時計から求めます。
    private var currentElapsed: TimeInterval {
        guard let startedAt else { return 0 }
        var pausing: TimeInterval = 0
        if let pausedAt { pausing = Date().timeIntervalSince(pausedAt) }
        return Date().timeIntervalSince(startedAt) - pausedTotal - pausing
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshStatistics()
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func refreshStatistics() {
        var updated = TrackMath.statistics(for: points)
        updated.elapsed = currentElapsed
        statistics = updated
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationTracker: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if startWhenAuthorized {
                startWhenAuthorized = false
                beginUpdates()
            }
        case .denied, .restricted:
            startWhenAuthorized = false
            problem = .permissionDenied
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            latest = location
            guard state == .recording, isUsable(location) else { continue }
            points.append(TrackPoint(location))
        }
        if state == .recording {
            refreshStatistics()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 一時的に測位できないだけのことが多いので、記録は止めずに無視する。
        // 権限の問題は locationManagerDidChangeAuthorization 側で扱う。
    }

    /// 記録に採用してよい測位結果か。
    private func isUsable(_ location: CLLocation) -> Bool {
        // 精度が取れていない、または誤差が大きすぎる点は軌跡を乱すので捨てる。
        guard location.horizontalAccuracy > 0,
              location.horizontalAccuracy <= TrackMath.accuracyLimit else { return false }

        // 起動直後に渡されるキャッシュ済みの古い位置を弾く。
        guard location.timestamp.timeIntervalSinceNow > -10 else { return false }

        return true
    }
}
