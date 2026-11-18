import CoreLocation
import Foundation

/// 天気を取得できなかったときに、代わりに見てもらう場所。
///
/// このアプリの予報は Open-Meteo の1か所だけに頼っています。そこが落ちていると
/// 画面には何も出せません。そのときに「取得できませんでした」で終わらせると、
/// 利用者は山に行くかどうかを決められないままになります。
///
/// どれも登山の前に実際に使われている先です。山頂の座標で開けるものを先に置いています。
enum WeatherLink: CaseIterable, Identifiable {
    /// 座標を指定して開ける。風と気温を高度別に見られるので、山では重宝します。
    case windy
    /// 日本の公式。警報・注意報はここが基準になります。
    case jma
    /// 山ごとの天気。登山者に広く使われています。
    case tenkiMountain

    var id: String { title }

    var title: String {
        switch self {
        case .windy: "Windy"
        case .jma: "気象庁"
        case .tenkiMountain: "tenki.jp 山の天気"
        }
    }

    var detail: String {
        switch self {
        case .windy: "この山頂の座標で開きます"
        case .jma: "警報・注意報の基準になる公式の予報"
        case .tenkiMountain: "山ごとの予報。山を選び直す必要があります"
        }
    }

    var symbolName: String {
        switch self {
        case .windy: "wind"
        case .jma: "building.columns"
        case .tenkiMountain: "mountain.2"
        }
    }

    /// 山頂の座標で開くURL。座標を使わない先では、そのまま入口を返します。
    func url(for coordinate: CLLocationCoordinate2D) -> URL? {
        switch self {
        case .windy:
            // 「?緯度,経度,ズーム」で、その地点を中心に開きます。
            let latitude = String(format: "%.4f", coordinate.latitude)
            let longitude = String(format: "%.4f", coordinate.longitude)
            return URL(string: "https://www.windy.com/?\(latitude),\(longitude),11")
        case .jma:
            return URL(string: "https://www.jma.go.jp/bosai/forecast/")
        case .tenkiMountain:
            return URL(string: "https://tenki.jp/mountain/")
        }
    }
}
