import CoreLocation
import Foundation

/// 軌跡から算出した数値。
struct TrackStatistics: Equatable, Codable {
    /// 水平距離の合計（メートル）
    var distance: Double = 0
    /// 累積標高（上り・メートル）
    var elevationGain: Double = 0
    /// 累積標高（下り・メートル）
    var elevationLoss: Double = 0
    /// 最初の点から最後の点までの経過時間（休憩込み）
    var elapsed: TimeInterval = 0
    /// 実際に動いていた時間（休憩を除く）
    var moving: TimeInterval = 0
    /// 現在の標高（最後に標高が取れた点の値）
    var currentAltitude: Double?

    static let zero = TrackStatistics()
}

enum TrackMath {
    /// 標高の上下をこの値以下なら無視する（メートル）。
    ///
    /// GPS の標高は誤差が大きく、静止していても数メートル上下します。
    /// そのまま足し込むと累積標高が実際の数倍になるため、
    /// 「基準点から一定以上動いたときだけ加算する」ヒステリシス方式で均します。
    static let altitudeNoiseThreshold: Double = 3.0

    /// 2点間がこの距離未満なら「止まっていた」とみなす（メートル）。
    static let movingDistanceThreshold: Double = 1.0

    /// 2点間がこれ以上離れていたら、間が欠落したとみなして移動時間に加算しない（秒）。
    static let movingTimeGapLimit: TimeInterval = 60

    /// 水平精度がこれより悪い点は、記録に使わない（メートル）。
    static let accuracyLimit: Double = 50

    /// 軌跡全体の統計を計算する。
    static func statistics(for points: [TrackPoint]) -> TrackStatistics {
        guard points.count >= 2 else {
            var stats = TrackStatistics.zero
            stats.currentAltitude = points.last?.altitude
            return stats
        }

        var stats = TrackStatistics.zero
        stats.elapsed = points[points.count - 1].timestamp
            .timeIntervalSince(points[0].timestamp)

        // 標高のヒステリシス用の基準点。
        var altitudeReference: Double? = points.first(where: { $0.altitude != nil })?.altitude

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]

            // --- 距離 ---
            let segment = current.location.distance(from: previous.location)
            stats.distance += segment

            // --- 移動時間 ---
            let interval = current.timestamp.timeIntervalSince(previous.timestamp)
            if segment >= movingDistanceThreshold,
               interval > 0,
               interval <= movingTimeGapLimit {
                stats.moving += interval
            }

            // --- 累積標高 ---
            if let altitude = current.altitude {
                if let reference = altitudeReference {
                    let delta = altitude - reference
                    if delta > altitudeNoiseThreshold {
                        stats.elevationGain += delta
                        altitudeReference = altitude
                    } else if delta < -altitudeNoiseThreshold {
                        stats.elevationLoss += -delta
                        altitudeReference = altitude
                    }
                    // しきい値以内の揺れは、基準点を動かさず無視する。
                } else {
                    altitudeReference = altitude
                }
            }
        }

        stats.currentAltitude = points.last(where: { $0.altitude != nil })?.altitude
        return stats
    }
}

// MARK: - 表示用の整形

extension TrackStatistics {
    /// 「3.4 km」「850 m」
    var distanceText: String {
        if distance >= 1000 {
            String(format: "%.2f km", distance / 1000)
        } else {
            String(format: "%.0f m", distance)
        }
    }

    var elevationGainText: String { String(format: "%.0f m", elevationGain) }
    var elevationLossText: String { String(format: "%.0f m", elevationLoss) }

    var currentAltitudeText: String {
        guard let currentAltitude else { return "—" }
        return String(format: "%.0f m", currentAltitude)
    }

    var elapsedText: String { Self.durationText(elapsed) }
    var movingText: String { Self.durationText(moving) }

    /// 「2:35:10」形式。
    static func durationText(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "0:00:00" }
        let total = Int(interval)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
