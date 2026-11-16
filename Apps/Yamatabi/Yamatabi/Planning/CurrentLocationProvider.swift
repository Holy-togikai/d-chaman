import CoreLocation

/// 現在地を1回だけ取得する。
///
/// 登山中の継続記録は `LocationTracker` の担当です。こちらは計画づくりで
/// 「出発地＝いまいる場所」を入れるためだけに使う、使い捨ての取得役です。
@MainActor
final class CurrentLocationProvider: NSObject, ObservableObject {

    @Published private(set) var isLocating = false
    @Published var errorMessage: String?

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    /// 権限ダイアログの応答を待っている最中か。応答が来てから測位を頼みます。
    private var isWaitingForAuthorization = false

    enum Failure: LocalizedError {
        case permissionDenied
        case failed

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "位置情報の利用が許可されていません。設定アプリから許可してください。"
            case .failed:
                "現在地を取得できませんでした。しばらくしてからお試しください。"
            }
        }
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func current() async throws -> CLLocation {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            errorMessage = Failure.permissionDenied.errorDescription
            throw Failure.permissionDenied
        }

        isLocating = true
        errorMessage = nil

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            if manager.authorizationStatus == .notDetermined {
                // 許可を求めた直後に測位を頼んでも無視される。
                // 応答が来てから locationManagerDidChangeAuthorization 側で頼む。
                isWaitingForAuthorization = true
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(with result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        isWaitingForAuthorization = false
        isLocating = false
        if case .failure(let error) = result {
            errorMessage = (error as? Failure)?.errorDescription
                ?? Failure.failed.errorDescription
        }
        continuation.resume(with: result)
    }
}

extension CurrentLocationProvider: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard isWaitingForAuthorization else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                isWaitingForAuthorization = false
                self.manager.requestLocation()
            case .denied, .restricted:
                finish(with: .failure(Failure.permissionDenied))
            default:
                break   // まだ応答が来ていない
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor in finish(with: .success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(with: .failure(Failure.failed)) }
    }
}
