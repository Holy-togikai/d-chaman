import CoreLocation
import SwiftUI

/// 山頂の天気を表示するセクション。
struct PlanWeatherSection: View {
    let forecast: [DailyWeather]
    let date: Date
    /// 山頂の座標。取得できなかったときに、代わりの天気サイトを開くのに使います。
    let summit: CLLocationCoordinate2D
    let isLoading: Bool
    let failure: WeatherService.Failure?
    let onRetry: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("取得中…").foregroundStyle(.secondary)
                }
            } else if let failure {
                failureContent(failure)
            } else if let day = dayForDate {
                summary(day)
                if let warning = day.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } else {
                // 予報の期間外。これは不具合ではないので、代わりの手段も出しません。
                // どこで調べても、まだ予報は出ていないためです。
                Text("この日の予報はまだ出ていません。予報が出るのは約2週間先までです。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("山頂の天気")
        } footer: {
            Text("気象データ: Open-Meteo.com（CC BY 4.0）。山頂の標高を加味した予報です。")
        }
    }

    // MARK: - 取得できなかったとき

    @ViewBuilder
    private func failureContent(_ failure: WeatherService.Failure) -> some View {
        Label(
            failure.errorDescription ?? "天気予報を取得できませんでした。",
            systemImage: "cloud.slash"
        )
        .font(.callout)
        .foregroundStyle(.secondary)

        if failure.isWorthRetrying {
            Button(action: onRetry) {
                Label("もう一度試す", systemImage: "arrow.clockwise")
            }
        }

        // 山に行くかどうかは天気で決まります。取れなかったで終わらせず、
        // ほかで調べられる場所を出します。
        ForEach(WeatherLink.allCases) { link in
            if let url = link.url(for: summit) {
                Button {
                    openURL(url)
                } label: {
                    LabeledContent {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label(link.title, systemImage: link.symbolName)
                        Text(link.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 取得できたとき

    private var dayForDate: DailyWeather? {
        let calendar = Calendar.current
        return forecast.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func summary(_ day: DailyWeather) -> some View {
        HStack(spacing: 14) {
            Image(systemName: day.code.symbolName)
                .font(.title)
                .symbolRenderingMode(.multicolor)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(day.code.label).font(.body.weight(.medium))
                Text(
                    "\(Int(day.temperatureMax))℃ / \(Int(day.temperatureMin))℃"
                    + " ・ 降水 \(day.precipitationProbability)%"
                    + " ・ 風 \(Int(day.windSpeed))m/s"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
