import SwiftUI

/// 記録中にTOPへ出す帯。地図を見ていなくても、いま動いていることが分かるように。
struct HomeRecordingBanner: View {
    let state: LocationTracker.State
    let statistics: TrackStatistics
    /// 下山期限までの残り。計算できないときは nil。
    let remainingUntilDeadline: TimeInterval?
    let onOpenMap: () -> Void

    var body: some View {
        Button(action: onOpenMap) {
            HStack(spacing: 14) {
                Image(systemName: state == .recording ? "record.circle" : "pause.circle")
                    .font(.system(size: 34))
                    .foregroundStyle(state == .recording ? Color.red : Color.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(statistics.distanceText) ・ ↑\(statistics.elevationGainText)")
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.brandGreen.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        guard let remainingUntilDeadline else {
            return state == .recording ? "記録中" : "一時停止中"
        }
        if remainingUntilDeadline <= 0 { return "下山の目安時刻を過ぎています" }
        return "下山まで あと\(TrackStatistics.hourMinuteText(remainingUntilDeadline))"
    }
}
