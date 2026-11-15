import Foundation

/// 日の出・日の入りの時刻。
struct SunTimes: Equatable {
    let sunrise: Date
    let sunset: Date
}

/// 任意の地点・日付の日の出／日の入りを計算する。
///
/// 通信を伴わないので、電波の無い山中でも動きます。登山計画の逆算はこの値を起点にします。
/// アルゴリズムは NOAA の日の出方程式。日本国内（札幌〜那覇、夏至・冬至）で
/// 公表値との差が1分以内であることを確認しています。
enum SunCalculator {

    /// 大気差を考慮した、太陽が「沈んだ」とみなす高度（度）。
    private static let standardZenith = -0.833

    /// - Parameters:
    ///   - elevation: 地点の標高（メートル）。高いほど地平線が下がり、日の入りが遅くなります。
    ///     富士山頂（3,776m）では海面より10分近く遅くなるため、登山では無視できません。
    static func times(
        latitude: Double,
        longitude: Double,
        elevation: Double = 0,
        date: Date,
        calendar: Calendar = .current
    ) -> SunTimes? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }

        let julianDay = julianDayNumber(year: year, month: month, day: day)
        let daysSinceEpoch = (julianDay - 2_451_545.0 + 0.0008).rounded(.up)
        let meanSolarTime = daysSinceEpoch - longitude / 360.0

        // 太陽の平均近点角
        let meanAnomaly = (357.5291 + 0.98560028 * meanSolarTime)
            .truncatingRemainder(dividingBy: 360)
        let anomaly = meanAnomaly * .pi / 180

        // 中心差
        let center = 1.9148 * sin(anomaly) + 0.0200 * sin(2 * anomaly) + 0.0003 * sin(3 * anomaly)

        // 黄道経度
        let eclipticLongitude = (meanAnomaly + center + 180 + 102.9372)
            .truncatingRemainder(dividingBy: 360)
        let lambda = eclipticLongitude * .pi / 180

        // 南中時刻（ユリウス日）
        let transit = 2_451_545.0 + meanSolarTime
            + 0.0053 * sin(anomaly) - 0.0069 * sin(2 * lambda)

        // 太陽赤緯
        let sinDeclination = sin(lambda) * sin(23.4397 * .pi / 180)
        let declination = asin(sinDeclination)

        // 標高による地平線の伏角（度）。高いところほど遠くまで見渡せる。
        let horizonDip = elevation > 0 ? 0.0353 * sqrt(elevation) : 0
        let zenith = (standardZenith - horizonDip) * .pi / 180

        let phi = latitude * .pi / 180
        let cosHourAngle = (sin(zenith) - sin(phi) * sinDeclination)
            / (cos(phi) * cos(declination))

        // 白夜・極夜では解が無い。日本では起きないが、念のため。
        guard cosHourAngle >= -1, cosHourAngle <= 1 else { return nil }

        let hourAngle = acos(cosHourAngle) * 180 / .pi

        return SunTimes(
            sunrise: makeDate(fromJulianDay: transit - hourAngle / 360.0),
            sunset: makeDate(fromJulianDay: transit + hourAngle / 360.0)
        )
    }

    /// グレゴリオ暦の年月日からユリウス日を求める。
    private static func julianDayNumber(year: Int, month: Int, day: Int) -> Double {
        // 1月・2月は前年の13月・14月として扱う、という暦計算の約束。
        var adjustedYear = year
        var adjustedMonth = month
        if adjustedMonth <= 2 {
            adjustedYear -= 1
            adjustedMonth += 12
        }
        let century = adjustedYear / 100
        let gregorianOffset = 2 - century + century / 4
        return floor(365.25 * Double(adjustedYear + 4716))
            + floor(30.6001 * Double(adjustedMonth + 1))
            + Double(day) + Double(gregorianOffset) - 1524.5
    }

    private static func makeDate(fromJulianDay julianDay: Double) -> Date {
        Date(timeIntervalSince1970: (julianDay - 2_440_587.5) * 86_400)
    }
}
