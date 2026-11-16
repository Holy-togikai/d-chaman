import SwiftUI

/// アプリアイコンと同じ山の形。
///
/// 大きな円の上側だけを見せる、という作りをアイコンから借りています。
/// 稜線の丸みをアイコンと揃えるため、半径は幅に対する比で決めています。
struct MountainSilhouette: Shape {
    /// 稜線の位置。枠の上端からの割合で、小さいほど山が高くなります。
    var ridgeRatio: CGFloat = 0.62

    func path(in rect: CGRect) -> Path {
        // 半径を小さくするほど稜線が丸くなる。アイコンの丸みに近い比率にしている。
        let radius = rect.width * 0.62
        // 円の上端が稜線になるよう中心を置く。円の下半分は枠からはみ出すので、
        // 呼び出し側で clip して枠の下端で自然に切れるようにする。
        let center = CGPoint(x: rect.midX, y: rect.minY + rect.height * ridgeRatio + radius)
        var path = Path()
        path.addEllipse(
            in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        return path
    }
}

/// まだ何も無い画面の案内。
///
/// 標準の `ContentUnavailableView` ではどのアプリでも同じ見た目になるため、
/// アイコンの山を下に敷いて、このアプリの画面だと分かるようにしています。
struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "mountain.2"

    var body: some View {
        ZStack(alignment: .bottom) {
            // 稜線は薄く。主役はあくまで文言なので、背景として置く。
            MountainSilhouette()
                .fill(Color.brandGreen.opacity(0.22))

            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.brandGreen.opacity(0.55))

                Text(title)
                    .font(.title3.weight(.semibold))

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    // アイコンの余白の多さに合わせて、文字を詰め込まない。
                    .padding(.horizontal, 40)
            }
            .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 円の下半分を枠の外に逃がしているので、ここで切り取る。
        .clipped()
    }
}

#Preview {
    EmptyStateView(
        title: "記録がありません",
        message: "山を選んで「記録を開始」すると、ここに残ります。",
        systemImage: "figure.hiking"
    )
}
