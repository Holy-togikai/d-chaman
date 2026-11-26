import CoreLocation
import Foundation
import Testing

@testable import Yamatabi

/// 天気が取れなかったときの振る舞い。
///
/// 予報は Open-Meteo の1か所だけに頼っています。そこが落ちると画面に何も出せません。
/// 「取得できませんでした」で終わらせると、山に行くかどうかを決められないままになります。
struct WeatherTests {

    /// 富士山（剣ヶ峯）。
    private static let fuji = CLLocationCoordinate2D(latitude: 35.3606, longitude: 138.7274)

    // MARK: - 代わりに見てもらう場所

    @Test func 代わりの行き先がすべてURLを返す() throws {
        for link in WeatherLink.allCases {
            let url = try #require(link.url(for: Self.fuji), "\(link.title) のURLが作れません")
            #expect(url.scheme == "https", "\(link.title) が https ではありません")
            #expect(!url.absoluteString.isEmpty)
        }
    }

    /// Windy は座標で開けるので、その山頂が最初から表示されます。
    @Test func Windyは山頂の座標つきで開く() throws {
        let url = try #require(WeatherLink.windy.url(for: Self.fuji))
        let text = url.absoluteString
        #expect(text.contains("35.3606"), "緯度が入っていません: \(text)")
        #expect(text.contains("138.7274"), "経度が入っていません: \(text)")
    }

    /// 座標を使わない先は、どの山でも同じ入口になります。
    @Test func 座標を使わない行き先は山によらず同じ() throws {
        let kita = CLLocationCoordinate2D(latitude: 35.6745, longitude: 138.2389)
        for link in [WeatherLink.jma, .tenkiMountain] {
            let a = try #require(link.url(for: Self.fuji))
            let b = try #require(link.url(for: kita))
            #expect(a == b, "\(link.title) が山ごとに変わっています")
        }
    }

    @Test func 行き先には必ず説明が付く() {
        for link in WeatherLink.allCases {
            #expect(!link.title.isEmpty)
            #expect(!link.detail.isEmpty, "\(link.title) に説明がありません")
            #expect(!link.symbolName.isEmpty)
        }
    }

    // MARK: - 失敗の扱い

    /// 届かなかったときと通信の失敗は、もう一度試す価値があります。
    /// 形式の違いは、何度試しても直りません。
    @Test func もう一度試す価値があるかを区別する() {
        #expect(WeatherService.Failure.unreachable.isWorthRetrying)
        #expect(WeatherService.Failure.network(URLError(.unknown)).isWorthRetrying)
        #expect(!WeatherService.Failure.badResponse.isWorthRetrying)
    }

    @Test func どの失敗にも日本語の説明がある() {
        let failures: [WeatherService.Failure] = [
            .unreachable, .network(URLError(.timedOut)), .badResponse
        ]
        for failure in failures {
            let text = failure.errorDescription ?? ""
            #expect(!text.isEmpty, "説明がありません")
            #expect(!text.contains("Error"), "英語のエラー文が漏れています: \(text)")
        }
    }

    // MARK: - 控えの提供元（met.no）

    /// met.no の天気記号を読み替える。昼夜の区別は落とします。
    @Test(arguments: [
        ("clearsky_day", WeatherCode.clear),
        ("clearsky_night", WeatherCode.clear),
        ("fair_polartwilight", WeatherCode.mainlyClear),
        ("partlycloudy_day", WeatherCode.partlyCloudy),
        ("cloudy", WeatherCode.overcast),
        ("fog", WeatherCode.fog),
        ("lightrain", WeatherCode.drizzle),
        ("rain", WeatherCode.rain),
        ("heavyrain", WeatherCode.heavyRain),
        ("sleet", WeatherCode.freezingRain),
        ("snow", WeatherCode.snow),
        ("heavysnow", WeatherCode.heavySnow)
    ])
    func met_noの天気記号を読み替える(symbol: String, expected: WeatherCode) {
        #expect(
            WeatherCode(metNoSymbol: symbol) == expected,
            "\(symbol) → \(WeatherCode(metNoSymbol: symbol).label)"
        )
    }

    /// 雷は他の天気と組み合わさる。危ないほうを採ります。
    @Test(arguments: ["rainandthunder", "snowandthunder", "heavyrainandthunder_day"])
    func 雷が混じる記号は雷雨として扱う(symbol: String) {
        #expect(WeatherCode(metNoSymbol: symbol) == .thunderstorm)
    }

    @Test func 知らない記号は不明として扱う() {
        #expect(WeatherCode(metNoSymbol: "まだ無い記号") == .unknown)
    }

    /// 1日を代表する記号は、いちばん荒れているものを採ります。
    /// 平均を採ると、午後から雷雨という日が「くもり」になってしまいます。
    @Test func 荒天の度合いが順に並ぶ() {
        #expect(WeatherCode.thunderstorm.severity > WeatherCode.heavyRain.severity)
        #expect(WeatherCode.heavyRain.severity > WeatherCode.rain.severity)
        #expect(WeatherCode.rain.severity > WeatherCode.overcast.severity)
        #expect(WeatherCode.overcast.severity > WeatherCode.clear.severity)
    }

    /// 規約で求められる名乗り。名乗らないと 403 が返ります。
    /// 個人のメールアドレスは入れません（公開するアプリに埋め込むと誰でも読めるため）。
    @Test func metNoの名乗りにメールアドレスを入れていない() {
        #expect(!MetNoWeather.userAgent.isEmpty)
        #expect(!MetNoWeather.userAgent.contains("@"), "メールアドレスが埋め込まれています")
    }

    // MARK: - 降水の表示

    /// Open-Meteo は確率、met.no は雨量。無いものは無いままにします。
    @Test func 降水確率があれば確率を出す() {
        let day = Self.day(probability: 30, amount: nil)
        #expect(day.precipitationText == "降水 30%")
    }

    @Test func 降水確率が無ければ雨量を出す() {
        let day = Self.day(probability: nil, amount: 12.4)
        #expect(day.precipitationText == "雨量 12mm")
    }

    @Test func どちらも無ければ出さない() {
        #expect(Self.day(probability: nil, amount: nil).precipitationText == nil)
    }

    /// 降水確率が無くても、雨量が多ければ警告を出す。
    @Test func 雨量が多ければ警告を出す() {
        #expect(Self.day(probability: nil, amount: 15).warning != nil)
        #expect(Self.day(probability: nil, amount: 2).warning == nil)
    }

    private static func day(probability: Int?, amount: Double?) -> DailyWeather {
        DailyWeather(
            date: Date(),
            code: .overcast,
            temperatureMax: 5,
            temperatureMin: -3,
            precipitationProbability: probability,
            precipitationAmount: amount,
            windSpeed: 3
        )
    }

    // MARK: - 出典

    /// どちらの提供元も、出典の表示が利用の条件です。
    @Test func どの提供元にも出典の表示がある() {
        for source in [WeatherSource.openMeteo, .metNo] {
            #expect(!source.attribution.isEmpty)
        }
        #expect(WeatherSource.openMeteo.attribution.contains("Open-Meteo"))
        #expect(WeatherSource.metNo.attribution.contains("MET Norway"))
    }

    /// 主は met.no、控えは Open-Meteo（決定記録 0003）。
    @Test func 控えから取ったことが分かる() {
        #expect(!WeatherSource.metNo.isFallback)
        #expect(WeatherSource.openMeteo.isFallback)
    }

    /// met.no の規約は、座標を小数4桁までに丸めるよう求めている。
    @Test func metNoの覚え書きは座標を4桁に丸める() {
        let a = MetNoCache.key(latitude: 35.360_61, longitude: 138.727_44, elevation: 3776.2)
        let b = MetNoCache.key(latitude: 35.360_64, longitude: 138.727_41, elevation: 3775.8)
        #expect(a == b, "\(a) と \(b)")
        #expect(a == "35.3606,138.7274,3776")
    }

    /// 期限までは覚えた予報を返し、期限を過ぎたら取り直す。
    @Test func metNoの覚え書きは期限まで使う() async {
        let cache = MetNoCache()
        let now = Date()
        let day = Self.day(probability: nil, amount: 1)
        await cache.store([day], for: "k", until: now.addingTimeInterval(60))
        #expect(await cache.days(for: "k", now: now) == [day])
        #expect(await cache.days(for: "k", now: now.addingTimeInterval(61)) == nil)
    }

    @Test func metNoのExpires見出しを読む() throws {
        let url = try #require(URL(string: "https://api.met.no/"))
        let response = try #require(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Expires": "Fri, 27 Nov 2026 12:30:00 GMT"]
        ))
        let expires = try #require(MetNoCache.expires(from: response))
        #expect(expires.timeIntervalSince1970 == 1_795_782_600)
    }

    /// 待つ上限を長くしすぎない。
    ///
    /// 既定の60秒だと、サーバーに届かないときに1分間「取得中…」のまま固まります。
    /// 待たされるより、早く諦めて代わりの手段を出すほうが役に立ちます。
    @Test func 待つ上限が短く保たれている() {
        #expect(
            WeatherService.timeout <= 15,
            "待ちすぎです。実際は \(Int(WeatherService.timeout))秒"
        )
        #expect(WeatherService.timeout >= 5, "短すぎると電波が弱いだけで諦めます")
    }
}
