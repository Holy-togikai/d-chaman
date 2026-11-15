import Foundation
import SwiftData

/// 1回の登山の記録。
///
/// 軌跡（`TrackPoint` の配列）は JSON にして `pointsData` に丸ごと格納します。
/// 1点ずつ SwiftData のレコードにすると、1回の登山で数千件になり読み書きが重くなるためです。
/// 代わりに、一覧表示で使う統計値は保存時に計算して列として持たせ、
/// 毎回軌跡を展開しなくても済むようにしています。
@Model
final class HikeRecord {
    var id: UUID = UUID()
    /// 登った山の名前。山を選ばずに記録を始めた場合は nil。
    var mountainName: String?
    var startedAt: Date = Date()
    var endedAt: Date?

    /// 軌跡の JSON。直接触らず `points` を使ってください。
    var pointsData: Data = Data()

    // --- 保存時に確定させる統計値（一覧表示用のキャッシュ）---
    var distance: Double = 0
    var elevationGain: Double = 0
    var elevationLoss: Double = 0
    var elapsedDuration: TimeInterval = 0
    var movingDuration: TimeInterval = 0

    init(
        mountainName: String?,
        startedAt: Date,
        endedAt: Date?,
        points: [TrackPoint],
        statistics: TrackStatistics
    ) {
        self.id = UUID()
        self.mountainName = mountainName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.points = points
        self.distance = statistics.distance
        self.elevationGain = statistics.elevationGain
        self.elevationLoss = statistics.elevationLoss
        self.elapsedDuration = statistics.elapsed
        self.movingDuration = statistics.moving
    }

    /// 軌跡。読み書きのたびに JSON を変換します。
    var points: [TrackPoint] {
        get {
            guard !pointsData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([TrackPoint].self, from: pointsData)) ?? []
        }
        set {
            pointsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    /// 保存済みの統計値から組み立て直したもの。軌跡を展開せずに使えます。
    var statistics: TrackStatistics {
        TrackStatistics(
            distance: distance,
            elevationGain: elevationGain,
            elevationLoss: elevationLoss,
            elapsed: elapsedDuration,
            moving: movingDuration,
            currentAltitude: nil
        )
    }

    var title: String {
        mountainName ?? "登山記録"
    }
}
