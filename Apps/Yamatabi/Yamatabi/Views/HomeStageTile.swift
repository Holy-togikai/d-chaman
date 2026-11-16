import SwiftUI

/// TOP画面で山行の流れを1枚ずつ出すタイル。
///
/// 絵記号を主役にして、文字は添えるだけにしています。山行中は手袋だったり
/// 日差しが強かったりで、細かい字を読んでいる余裕がないためです。
struct HomeStageTile: View {
    let stage: HikeStage
    let state: HikeProgress.State
    /// タイルの真ん中に大きく出す値。時刻や品数など、ひと目で分かる短いもの。
    let value: String?
    /// 値の下に小さく添える補足。
    let caption: String?
    /// 注意を引きたいタイル（買い出しが残っているなど）。
    var needsAttention = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: stage.symbolName)
                        .font(.system(size: 34, weight: .regular))
                        .frame(height: 38)
                    if state == .finished {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .offset(x: 10, y: -2)
                    }
                }
                .foregroundStyle(iconColor)

                Text(value ?? "—")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(stage.title)
                    .font(.caption2)
                    .foregroundStyle(subtleColor)

                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(subtleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(background, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.brandGreen.opacity(state == .current ? 0 : 0.12))
            }
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        // 進行中だけを塗りつぶして、いま見るべきタイルが遠目にも分かるようにする。
        state == .current ? .brandGreenDeep : Color.brandGreen.opacity(0.07)
    }

    private var iconColor: Color {
        switch state {
        case .current: .white
        case .finished: Color.brandGreen.opacity(0.4)
        case .upcoming: needsAttention ? .orange : .brandGreen
        }
    }

    private var valueColor: Color {
        switch state {
        case .current: .white
        case .finished: .secondary
        case .upcoming: needsAttention ? .orange : .primary
        }
    }

    private var subtleColor: Color {
        state == .current ? Color.white.opacity(0.75) : .secondary
    }
}

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
