import SwiftUI

/// 山頂の天気を表示するセクション。
struct PlanWeatherSection: View {
    let forecast: [DailyWeather]
    let date: Date
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        Section {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("取得中…").foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.secondary)
            } else if let day = dayForDate {
                summary(day)
                if let warning = day.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } else {
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
