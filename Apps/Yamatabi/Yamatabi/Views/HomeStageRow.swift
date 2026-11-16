import SwiftUI

/// TOP画面で山行の流れを1段ずつ出す行。
struct HomeStageRow: View {
    let stage: HikeStage
    let state: HikeProgress.State
    /// 「前日 23:57 ・ 約2,600円」のような補足。
    let detail: String?
    /// 行の右端に出す短い値。移動時間など。
    var trailing: String?
    /// 注意を引きたい行（買い出しが残っているなど）。
    var needsAttention = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: state == .finished ? "checkmark.circle.fill" : stage.symbolName)
                    .font(.system(size: 15))
                    .foregroundStyle(iconColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stage.title)
                        .font(.subheadline)
                        .fontWeight(state == .current ? .semibold : .regular)
                        .strikethrough(state == .finished)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(needsAttention ? Color.orange : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                if let trailing {
                    Text(trailing)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            // 済んだ行は薄くして、いま見るべき行から目を離させない。
            .opacity(state == .finished ? 0.5 : 1)
        }
        .tint(.primary)
    }

    private var iconColor: Color {
        switch state {
        case .finished: .secondary
        case .current: .brandGreen
        case .upcoming: needsAttention ? .orange : .secondary
        }
    }
}

/// 記録中にTOPへ出す帯。地図を見ていなくても、いま動いていることが分かるように。
struct HomeRecordingBanner: View {
    let state: LocationTracker.State
    let statistics: TrackStatistics
    let mountainName: String?
    /// 下山期限までの残り。計算できないときは nil。
    let remainingUntilDeadline: TimeInterval?
    let onOpenMap: () -> Void

    var body: some View {
        Button(action: onOpenMap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(state == .recording ? Color.red : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(state == .recording ? "記録中" : "一時停止中")
                        .font(.caption.weight(.semibold))
                    if let mountainName {
                        Text("・\(mountainName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("\(statistics.distanceText) ・ 登り \(statistics.elevationGainText)")
                    .font(.title3.weight(.semibold).monospacedDigit())

                if let remainingUntilDeadline, remainingUntilDeadline > 0 {
                    Text("下山まで あと\(TrackStatistics.hourMinuteText(remainingUntilDeadline))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if remainingUntilDeadline != nil {
                    Text("下山の目安時刻を過ぎています")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(.primary)
    }
}
