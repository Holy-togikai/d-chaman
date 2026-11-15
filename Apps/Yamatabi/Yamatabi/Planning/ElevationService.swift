import Foundation

/// 任意の地点の標高を国土地理院から取得する。
///
/// 登山口の標高が分かると、山頂との差からコースタイムを見積もれます。
/// 出典: 国土地理院 標高API
/// https://maps.gsi.go.jp/development/elevation_s.html
enum ElevationService {

    enum Failure: LocalizedError {
        case network(Error)
        case unavailable

        var errorDescription: String? {
            switch self {
            case .network: "標高を取得できませんでした。通信状況をご確認ください。"
            case .unavailable: "この地点の標高データがありません。"
            }
        }
    }

    static func elevation(latitude: Double, longitude: Double) async throws -> Double {
        var components = URLComponents(
            string: "https://cyberjapandata2.gsi.go.jp/general/dem/scripts/getelevation.php"
        )!
        components.queryItems = [
            .init(name: "lon", value: String(longitude)),
            .init(name: "lat", value: String(latitude)),
            .init(name: "outtype", value: "JSON")
        ]

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: components.url!)
        } catch {
            throw Failure.network(error)
        }

        guard let response = try? JSONDecoder().decode(ElevationResponse.self, from: data),
              let elevation = response.elevationValue else {
            throw Failure.unavailable
        }
        return elevation
    }
}

/// 海上などデータが無い地点では、elevation に数値ではなく "-----" が返ります。
private struct ElevationResponse: Decodable {
    let elevation: ElevationValue

    var elevationValue: Double? {
        if case .number(let value) = elevation { return value }
        return nil
    }
}

private enum ElevationValue: Decodable {
    case number(Double)
    case missing

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .missing
        }
    }
}
