import Foundation

/// 1日ぶんの山の天気。
struct DailyWeather: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let code: WeatherCode
    let temperatureMax: Double
    let temperatureMin: Double
    /// 降水確率（%）
    let precipitationProbability: Int
    /// 最大風速（m/s）
    let windSpeed: Double

    /// 登山を見送るべきか判断する材料。危険側に倒して判定します。
    var warning: String? {
        if windSpeed >= 15 { return "風が強すぎます（\(Int(windSpeed))m/s）" }
        if code.isSevere { return "荒天の予報です" }
        if precipitationProbability >= 70 { return "降水確率が高めです（\(precipitationProbability)%）" }
        if windSpeed >= 10 { return "風がやや強めです（\(Int(windSpeed))m/s）" }
        return nil
    }
}

/// WMO の天気コード。Open-Meteo が返す数値に対応します。
enum WeatherCode: Int, Equatable {
    case clear = 0
    case mainlyClear = 1
    case partlyCloudy = 2
    case overcast = 3
    case fog = 45
    case rimeFog = 48
    case drizzle = 51
    case rain = 61
    case heavyRain = 65
    case freezingRain = 66
    case snow = 71
    case heavySnow = 75
    case snowGrains = 77
    case rainShowers = 80
    case snowShowers = 85
    case thunderstorm = 95
    case thunderstormHail = 99
    case unknown = -1

    init(rawCode: Int) {
        self = WeatherCode(rawValue: rawCode) ?? WeatherCode.closest(to: rawCode)
    }

    /// Open-Meteo は 53/55、63、72/73 などの中間値も返すので、近いものに寄せる。
    private static func closest(to code: Int) -> WeatherCode {
        switch code {
        case 51...57: .drizzle
        case 61...64: .rain
        case 65, 67: .heavyRain
        case 66: .freezingRain
        case 71...74: .snow
        case 75, 76: .heavySnow
        case 80...82: .rainShowers
        case 85, 86: .snowShowers
        case 95...99: .thunderstorm
        default: .unknown
        }
    }

    var label: String {
        switch self {
        case .clear: "快晴"
        case .mainlyClear: "晴れ"
        case .partlyCloudy: "晴れ時々くもり"
        case .overcast: "くもり"
        case .fog: "霧"
        case .rimeFog: "霧（着氷）"
        case .drizzle: "霧雨"
        case .rain: "雨"
        case .heavyRain: "強い雨"
        case .freezingRain: "着氷性の雨"
        case .snow: "雪"
        case .heavySnow: "大雪"
        case .snowGrains: "霧雪"
        case .rainShowers: "にわか雨"
        case .snowShowers: "にわか雪"
        case .thunderstorm: "雷雨"
        case .thunderstormHail: "雷雨（ひょう）"
        case .unknown: "—"
        }
    }

    var symbolName: String {
        switch self {
        case .clear, .mainlyClear: "sun.max.fill"
        case .partlyCloudy: "cloud.sun.fill"
        case .overcast: "cloud.fill"
        case .fog, .rimeFog: "cloud.fog.fill"
        case .drizzle, .rain, .rainShowers: "cloud.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .freezingRain: "cloud.sleet.fill"
        case .snow, .snowGrains, .snowShowers: "cloud.snow.fill"
        case .heavySnow: "snowflake"
        case .thunderstorm, .thunderstormHail: "cloud.bolt.rain.fill"
        case .unknown: "questionmark"
        }
    }

    /// 登山を取りやめる判断材料になる荒天か。
    var isSevere: Bool {
        switch self {
        case .heavyRain, .freezingRain, .heavySnow, .thunderstorm, .thunderstormHail:
            true
        default:
            false
        }
    }
}

/// 山頂の天気予報を取得する。
///
/// 提供元: Open-Meteo（https://open-meteo.com）。APIキー不要で、
/// 緯度経度を指定すると標高を加味した予報が返ります。山の上の気温を知るうえで重要です。
/// データは CC BY 4.0。画面に出典を表示しています。
///
/// 予報が出ているのはおよそ2週間先までで、それより先の登山日では結果が空になります。
enum WeatherService {

    enum Failure: LocalizedError {
        case network(Error)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .network: "天気予報を取得できませんでした。通信状況をご確認ください。"
            case .badResponse: "天気予報の形式が想定と違いました。"
            }
        }
    }

    static func forecast(
        latitude: Double,
        longitude: Double,
        days: Int = 14
    ) async throws -> [DailyWeather] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "daily", value: [
                "weather_code",
                "temperature_2m_max",
                "temperature_2m_min",
                "precipitation_probability_max",
                "wind_speed_10m_max"
            ].joined(separator: ",")),
            // 風速は登山では m/s で語られるので、km/h ではなくこちらで受け取る。
            .init(name: "wind_speed_unit", value: "ms"),
            .init(name: "timezone", value: "Asia/Tokyo"),
            .init(name: "forecast_days", value: String(days))
        ]

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: components.url!)
        } catch {
            throw Failure.network(error)
        }

        guard let response = try? JSONDecoder().decode(OpenMeteoResponse.self, from: data) else {
            throw Failure.badResponse
        }
        return response.toDailyWeather()
    }
}

// MARK: - Open-Meteo のレスポンス

private struct OpenMeteoResponse: Decodable {
    let daily: OpenMeteoDaily

    func toDailyWeather() -> [DailyWeather] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")

        return daily.time.indices.compactMap { index in
            guard let date = formatter.date(from: daily.time[index]) else { return nil }
            return DailyWeather(
                date: date,
                code: WeatherCode(rawCode: daily.weatherCode[index]),
                temperatureMax: daily.temperatureMax[index] ?? 0,
                temperatureMin: daily.temperatureMin[index] ?? 0,
                precipitationProbability: daily.precipitationProbability[index] ?? 0,
                windSpeed: daily.windSpeed[index] ?? 0
            )
        }
    }
}

private struct OpenMeteoDaily: Decodable {
    let time: [String]
    let weatherCode: [Int]
    let temperatureMax: [Double?]
    let temperatureMin: [Double?]
    let precipitationProbability: [Int?]
    let windSpeed: [Double?]

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperatureMax = "temperature_2m_max"
        case temperatureMin = "temperature_2m_min"
        case precipitationProbability = "precipitation_probability_max"
        case windSpeed = "wind_speed_10m_max"
    }
}
