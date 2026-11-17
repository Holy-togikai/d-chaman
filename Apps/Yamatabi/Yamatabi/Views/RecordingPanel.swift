import SwiftUI

/// 画面下部の記録パネル。待機中は開始ボタン、記録中は数値と操作ボタンを出します。
struct RecordingPanel: View {
    let state: LocationTracker.State
    let statistics: TrackStatistics
    /// 記録対象として選ばれている山。未選択なら nil。
    let mountainName: String?

    let onStart: () -> Void
    /// 選んだ山で計画を立てる。山を選んでいないときは nil。
    var onPlan: (() -> Void)?
    let onPause: () -> Void
    let onResume: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if state == .idle {
                idleContent
            } else {
                recordingContent
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .shadow(color: .black.opacity(0.12), radius: 10, y: -2)
    }

    // MARK: - 待機中

    /// 山を選んだ直後に出す。
    ///
    /// 地図で山を選ぶのは、たいてい「いつか登るために調べている」ときです。
    /// その場で歩き出すことはまずないので、計画を立てるほうを主役にしています。
    /// 登山口に着いてから開く道も残したいので、記録はその下に小さく置きます。
    @ViewBuilder
    private var idleContent: some View {
        if let onPlan, mountainName != nil {
            VStack(spacing: 12) {
                Button(action: onPlan) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.plus")
                        Text("この山で登山計画を立てる")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.brandGreen, in: Capsule())
                    .foregroundStyle(.white)
                }

                Button(action: onStart) {
                    Label("いま記録を開始する", systemImage: "figure.hiking")
                        .font(.subheadline)
                }
                .tint(.brandGreen)
            }
        } else {
            Button(action: onStart) {
                HStack(spacing: 8) {
                    Image(systemName: "figure.hiking")
                    Text("記録を開始")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.brandGreen, in: Capsule())
                .foregroundStyle(.white)
            }
        }
    }

    // MARK: - 記録中・一時停止中

    private var recordingContent: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle()
                    .fill(state == .recording ? Color.red : Color.orange)
                    .frame(width: 8, height: 8)
                Text(state == .recording ? "記録中" : "一時停止中")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let mountainName {
                    Text("・\(mountainName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 0) {
                metric("距離", statistics.distanceText)
                divider
                metric("のぼり", statistics.elevationGainText)
                divider
                metric("時間", statistics.elapsedText)
                divider
                metric("標高", statistics.currentAltitudeText)
            }

            HStack(spacing: 12) {
                if state == .recording {
                    secondaryButton("一時停止", icon: "pause.fill", action: onPause)
                } else {
                    secondaryButton("再開", icon: "play.fill", action: onResume)
                }

                Button(action: onFinish) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                        Text("終了")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.red, in: Capsule())
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 1, height: 28)
    }

    private func secondaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .fontWeight(.medium)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.primary)
        }
    }
}
