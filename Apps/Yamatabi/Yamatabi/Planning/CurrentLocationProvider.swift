import CoreLocation

/// 現在地を1回だけ取得する。
///
/// 登山中の継続記録は `LocationTracker` の担当です。こちらは計画づくりで
/// 「出発地＝いまいる場所」を入れるためだけに使う、使い捨ての取得役です。
@MainActor
final class CurrentLocationProvider: NSObject, ObservableObject {

    @Published private(set) var isLocating = false
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    enum Failure: LocalizedError {
        case permissionDenied
        case failed

        var errorDescription: String? {
            switch self {
            case .permissionDenied: "位置情報の利用が許可されていません。"
            case .failed: "現在地を取得できませんでした。"
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
            throw Failure.permissionDenied
        }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }

        isLocating = true
        errorMessage = nil
        defer { isLocating = false }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    private func finish(with result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

extension CurrentLocationProvider: CLLocationManagerDelegate {

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor in finish(with: .success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            errorMessage = Failure.failed.errorDescription
            finish(with: .failure(Failure.failed))
        }
    }
}
