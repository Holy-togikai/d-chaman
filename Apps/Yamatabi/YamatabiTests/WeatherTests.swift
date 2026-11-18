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
