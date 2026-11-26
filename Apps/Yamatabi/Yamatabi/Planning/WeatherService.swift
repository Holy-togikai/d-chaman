import Foundation

/// 1日ぶんの山の天気。
struct DailyWeather: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let code: WeatherCode
    let temperatureMax: Double
    let temperatureMin: Double
    /// 降水確率（%）。met.no は日本向けに出さないため、そのときは nil。
    let precipitationProbability: Int?
    /// 降水量（mm）。Open-Meteo からは取っていないため、そのときは nil。
    let precipitationAmount: Double?
    /// 最大風速（m/s）
    let windSpeed: Double

    /// 登山を見送るべきか判断する材料。危険側に倒して判定します。
    var warning: String? {
        if windSpeed >= 15 { return "風が強すぎます（\(Int(windSpeed))m/s）" }
        if code.isSevere { return "荒天の予報です" }
        if let probability = precipitationProbability, probability >= 70 {
            return "降水確率が高めです（\(probability)%）"
        }
        // 降水確率が無いときは降水量で見ます。1日10mmは、山では終日濡れる量です。
        if let amount = precipitationAmount, amount >= 10 {
            return "雨量が多めです（\(String(format: "%.0f", amount))mm）"
        }
        if windSpeed >= 10 { return "風がやや強めです（\(Int(windSpeed))m/s）" }
        return nil
    }

    /// 「降水 30%」「雨量 12mm」。どちらも無ければ空。
    var precipitationText: String? {
        if let precipitationProbability { return "降水 \(precipitationProbability)%" }
        if let precipitationAmount {
            return "雨量 \(String(format: "%.0f", precipitationAmount))mm"
        }
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

/// 予報の提供元。出典の表示に使います。どちらも表示が利用の条件です。
enum WeatherSource: Equatable {
    case openMeteo
    case metNo

    var attribution: String {
        switch self {
        case .openMeteo:
            "気象データ: Open-Meteo.com（CC BY 4.0）。山頂の標高を加味した予報です。"
        case .metNo:
            "気象データ: Meteorologisk institutt（MET Norway）。山頂の標高を加味した予報です。"
                + "この提供元は日本向けの降水確率を出さないため、雨量で表示しています。"
        }
    }

    /// 控えの提供元から取ったか。画面でその旨を添えるために使います。
    ///
    /// 主は met.no、控えは Open-Meteo（決定記録 0003）。
    var isFallback: Bool { self == .openMeteo }
}

/// 取得できた予報と、その出どころ。
struct WeatherForecast: Equatable {
    let days: [DailyWeather]
    let source: WeatherSource

    static let empty = WeatherForecast(days: [], source: .metNo)
}

/// 山頂の天気予報を取得する。
///
/// 主の提供元は met.no（MET Norway）、控えは Open-Meteo です（決定記録 0003）。
/// どちらも APIキー不要で、標高を加味した予報が返ります。山の上の気温を知るうえで重要です。
///
/// met.no を主にしたのは、出典を表示すれば**商用でも無料**で使えるためです。
/// Open-Meteo の無料版は商用ではない利用に限られ、将来の買い切り有料化と両立しません。
///
/// 予報が出ているのはおよそ2週間先までで、それより先の登山日では結果が空になります。
enum WeatherService {

    /// 待つ上限。
    ///
    /// 既定の60秒だと、サーバーに届かないときに1分間「取得中…」のまま固まります。
    /// 山で電波が弱いときほど起きやすく、待たされるより早く諦めて代わりの手段を
    /// 示すほうが役に立ちます。
    static let timeout: TimeInterval = 10

    /// met.no が駄目なときに Open-Meteo を控えとして使うか。
    ///
    /// **買い切りの有料版に切り替える前に、false にするか Open-Meteo の商用プランを契約すること。**
    /// Open-Meteo の無料版は商用ではない利用に限られるためです（決定記録 0003）。
    /// 無料で公開している間は、予報が取れない時間を減らすために控えとして残しています。
    static let usesOpenMeteoFallback = true

    enum Failure: LocalizedError {
        /// サーバーに届かなかった（圏外・タイムアウト・サーバー障害）。
        case unreachable
        case network(Error)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .unreachable:
                "天気予報サーバーに届きませんでした。"
            case .network:
                "天気予報を取得できませんでした。通信状況をご確認ください。"
            case .badResponse:
                "天気予報の形式が想定と違いました。"
            }
        }

        /// もう一度試す価値があるか。形式の違いは試しても直りません。
        var isWorthRetrying: Bool {
            switch self {
            case .unreachable, .network: true
            case .badResponse: false
            }
        }
    }

    /// URLError を、利用者から見た失敗の種類に直す。
    static func failure(for error: URLError) -> Failure {
        switch error.code {
        case .timedOut, .notConnectedToInternet, .networkConnectionLost,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            .unreachable
        default:
            .network(error)
        }
    }

    /// 予報を取る。met.no が駄目なら、控えの Open-Meteo を試す。
    ///
    /// 提供元が1つだと、そこが落ちている間は何も出せません。山に行くかどうかは
    /// 天気で決まるので、控えを持ちます。
    /// 両方駄目なときは、**最初の失敗**を投げます。利用者にとっては
    /// 「予報が取れなかった」という1つのことだからです。
    static func forecast(
        latitude: Double,
        longitude: Double,
        elevation: Double,
        days: Int = 14
    ) async throws -> WeatherForecast {
        let firstFailure: Error
        do {
            let metNo = try await MetNoWeather.forecast(
                latitude: latitude, longitude: longitude, elevation: elevation
            )
            // 空の配列が返ることもあるので、中身がないなら控えに回します。
            if !metNo.isEmpty {
                return WeatherForecast(days: metNo, source: .metNo)
            }
            firstFailure = Failure.badResponse
        } catch {
            firstFailure = error
        }

        guard usesOpenMeteoFallback else { throw firstFailure }
        do {
            let days = try await openMeteoForecast(latitude: latitude, longitude: longitude, days: days)
            guard !days.isEmpty else { throw firstFailure }
            return WeatherForecast(days: days, source: .openMeteo)
        } catch {
            // 控えも駄目なら、最初の失敗を伝えます。
            throw firstFailure
        }
    }

    private static func openMeteoForecast(
        latitude: Double,
        longitude: Double,
        days: Int
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

        let request = URLRequest(url: components.url!, timeoutInterval: timeout)
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            // 圏外・タイムアウト・名前解決の失敗は、どれも「届かなかった」として扱います。
            // 利用者にとっては同じことで、やることも同じ（電波を変えるか、別の手段で調べる）です。
            throw failure(for: error)
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
                precipitationProbability: daily.precipitationProbability[index],
                precipitationAmount: nil,
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
