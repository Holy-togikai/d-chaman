import Foundation

/// ノルウェー気象研究所（MET Norway）の予報。
///
/// このアプリの**主の提供元**です（決定記録 0003）。キー不要で、標高を指定でき、
/// 10日先まで返ります。日本の山でも使えます。出典を表示すれば商用でも無料です。
///
/// ## 利用の条件
///
/// - **出典の表示が必要です。** 画面に「Meteorologisk institutt (MET Norway)」を出しています
/// - **User-Agent でアプリを名乗る必要があります。** 名乗らないと 403 が返ります
/// - 同じ地点を何度も取りに行かないこと。返ってきた「Expires」の時刻までは、
///   同じ地点の予報を取りに行かず、手元のものを使います（`cache`）
///
/// ## Open-Meteo との違い
///
/// **降水確率が返りません。** met.no が確率を出すのは北欧だけで、日本では空です。
/// かわりに降水量（mm）が返るので、そちらを出します。確率を降水量から
/// でっち上げることはしません。根拠のない数字は出さないためです。
enum MetNoWeather {

    /// MET Norway の規約で求められる名乗り。
    ///
    /// 規約は連絡先を求めていますが、ここに個人のメールアドレスは書きません。
    /// 公開するアプリに埋め込むと、誰でも読めてしまうためです。
    /// 公開前に、問い合わせ用の窓口を決めて足してください。
    static let userAgent = "Yamatabi/0.1 (iOS hiking app)"

    /// 取った予報を、met.no が示す期限まで覚えておく。
    ///
    /// 主の提供元にしたことで、計画画面を開くたびに取りに行くことになります。
    /// 規約は「Expires までは取り直さない」ことを求めているので、それに従います。
    private static let cache = MetNoCache()

    static func forecast(
        latitude: Double,
        longitude: Double,
        elevation: Double,
        calendar: Calendar = .current
    ) async throws -> [DailyWeather] {
        // 規約が座標を小数4桁までに丸めるよう求めている。丸めると同じ地点として覚えられる。
        let key = MetNoCache.key(latitude: latitude, longitude: longitude, elevation: elevation)
        if let cached = await cache.days(for: key, now: Date()) {
            return cached
        }

        var components = URLComponents(
            string: "https://api.met.no/weatherapi/locationforecast/2.0/compact"
        )!
        components.queryItems = [
            .init(name: "lat", value: String(format: "%.4f", latitude)),
            .init(name: "lon", value: String(format: "%.4f", longitude)),
            // 標高を渡すと、山の上の気温として返ります。
            .init(name: "altitude", value: String(Int(elevation.rounded())))
        ]

        var request = URLRequest(url: components.url!, timeoutInterval: WeatherService.timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw WeatherService.failure(for: error)
        } catch {
            throw WeatherService.Failure.network(error)
        }

        // met.no は時刻を「2026-11-18T14:00:00Z」の形で返します。
        // 既定のままだと数値として読もうとして失敗するので、必ず指定します。
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let decoded = try? decoder.decode(MetNoResponse.self, from: data) else {
            throw WeatherService.Failure.badResponse
        }
        let days = decoded.toDailyWeather(calendar: calendar)
        let expires = MetNoCache.expires(from: response) ?? Date().addingTimeInterval(30 * 60)
        await cache.store(days, for: key, until: expires)
        return days
    }
}

// MARK: - 取った予報の覚え書き

/// met.no の予報を、返ってきた期限まで覚えておく係。
actor MetNoCache {
    private var entries: [String: (days: [DailyWeather], expires: Date)] = [:]

    func days(for key: String, now: Date) -> [DailyWeather]? {
        guard let entry = entries[key], now < entry.expires else { return nil }
        return entry.days
    }

    func store(_ days: [DailyWeather], for key: String, until expires: Date) {
        entries[key] = (days, expires)
    }

    /// 同じ地点とみなす鍵。規約に合わせて小数4桁に丸める。
    static func key(latitude: Double, longitude: Double, elevation: Double) -> String {
        String(format: "%.4f,%.4f,%d", latitude, longitude, Int(elevation.rounded()))
    }

    /// 応答の「Expires」見出しを読む。読めなければ nil。
    static func expires(from response: URLResponse) -> Date? {
        guard let value = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Expires") else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}

// MARK: - 天気記号の読み替え

extension WeatherCode {
    /// met.no の symbol_code（「partlycloudy_day」など）を読み替える。
    ///
    /// 末尾の `_day` `_night` `_polartwilight` は昼夜の区別なので落とします。
    init(metNoSymbol symbol: String) {
        var name = symbol
        for suffix in ["_day", "_night", "_polartwilight"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        // 雷は他の天気と組み合わさる（「rainandthunder」）。危ないほうを採ります。
        if name.contains("thunder") {
            self = .thunderstorm
            return
        }
        self = Self.metNoSymbols[name] ?? .unknown
    }

    /// met.no の記号と、このアプリの天気の対応。
    /// 分岐で書くより表のほうが、増えたときに見通しが利きます。
    private static let metNoSymbols: [String: WeatherCode] = [
        "clearsky": .clear,
        "fair": .mainlyClear,
        "partlycloudy": .partlyCloudy,
        "cloudy": .overcast,
        "fog": .fog,
        "lightrain": .drizzle,
        "lightrainshowers": .drizzle,
        "lightsleet": .drizzle,
        "lightsleetshowers": .drizzle,
        "rain": .rain,
        "rainshowers": .rain,
        "heavyrain": .heavyRain,
        "heavyrainshowers": .heavyRain,
        "sleet": .freezingRain,
        "sleetshowers": .freezingRain,
        "heavysleet": .freezingRain,
        "heavysleetshowers": .freezingRain,
        "lightsnow": .snow,
        "lightsnowshowers": .snow,
        "snow": .snow,
        "snowshowers": .snow,
        "heavysnow": .heavySnow,
        "heavysnowshowers": .heavySnow
    ]

    /// 荒天の度合い。1日を代表する記号を選ぶときに、危ないほうを採るために使います。
    var severity: Int {
        switch self {
        case .thunderstorm, .thunderstormHail: 6
        case .heavySnow, .heavyRain, .freezingRain: 5
        case .snow, .snowGrains, .snowShowers: 4
        case .rain, .rainShowers: 3
        case .drizzle, .fog, .rimeFog: 2
        case .overcast, .partlyCloudy: 1
        case .clear, .mainlyClear, .unknown: 0
        }
    }
}

// MARK: - met.no のレスポンス

private struct MetNoResponse: Decodable {
    let properties: Properties

    struct Properties: Decodable {
        let timeseries: [Entry]
    }

    struct Entry: Decodable {
        let time: Date
        let data: EntryData
    }

    struct EntryData: Decodable {
        let instant: Instant
        let next1Hours: Period?
        let next6Hours: Period?

        enum CodingKeys: String, CodingKey {
            case instant
            case next1Hours = "next_1_hours"
            case next6Hours = "next_6_hours"
        }
    }

    struct Instant: Decodable {
        let details: InstantDetails
    }

    struct InstantDetails: Decodable {
        let airTemperature: Double?
        let windSpeed: Double?

        enum CodingKeys: String, CodingKey {
            case airTemperature = "air_temperature"
            case windSpeed = "wind_speed"
        }
    }

    struct Period: Decodable {
        let summary: Summary?
        let details: PeriodDetails?
    }

    struct Summary: Decodable {
        let symbolCode: String

        enum CodingKeys: String, CodingKey {
            case symbolCode = "symbol_code"
        }
    }

    struct PeriodDetails: Decodable {
        let precipitationAmount: Double?

        enum CodingKeys: String, CodingKey {
            case precipitationAmount = "precipitation_amount"
        }
    }

    /// 1時間ごとの値を、日本時間の1日ごとにまとめる。
    func toDailyWeather(calendar: Calendar) -> [DailyWeather] {
        var jst = calendar
        jst.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? calendar.timeZone

        var byDay: [Date: [Entry]] = [:]
        for entry in properties.timeseries {
            byDay[jst.startOfDay(for: entry.time), default: []].append(entry)
        }

        return byDay.keys.sorted().compactMap { day in
            byDay[day].flatMap { Self.summarize(day: day, entries: $0) }
        }
    }

    /// 1日ぶんの時刻をまとめて、その日の予報にする。
    private static func summarize(day: Date, entries: [Entry]) -> DailyWeather? {
        let temperatures = entries.compactMap { $0.data.instant.details.airTemperature }
        guard let maxTemp = temperatures.max(), let minTemp = temperatures.min() else {
            // 気温が1つも無い日は、出しても意味がありません。
            return nil
        }

        // 降水量は二重に数えないよう、1時間ぶんがあればそれを、無ければ6時間ぶんを使う。
        let rain = entries.reduce(0.0) { total, entry in
            total + (entry.data.next1Hours?.details?.precipitationAmount
                ?? entry.data.next6Hours?.details?.precipitationAmount
                ?? 0)
        }

        // その日の記号は、いちばん荒れているものを採ります。
        // 平均を採ると、午後から雷雨という日が「くもり」になってしまいます。
        let codes = entries.compactMap { entry -> WeatherCode? in
            let symbol = entry.data.next1Hours?.summary?.symbolCode
                ?? entry.data.next6Hours?.summary?.symbolCode
            return symbol.map { WeatherCode(metNoSymbol: $0) }
        }

        return DailyWeather(
            date: day,
            code: codes.max { $0.severity < $1.severity } ?? .unknown,
            temperatureMax: maxTemp,
            temperatureMin: minTemp,
            // met.no は日本向けに降水確率を出しません。無いものは無いままにします。
            precipitationProbability: nil,
            precipitationAmount: rain,
            windSpeed: entries.compactMap { $0.data.instant.details.windSpeed }.max() ?? 0
        )
    }
}
