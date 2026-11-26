import MapKit
import UIKit

// MARK: - 出典表示

// 出典表示は地理院タイルの利用条件なので、地図の本体とは分けてまとめて置く。
extension GSIMapView {
    /// 「地理院タイル」の出典を地図の左下に重ねる。タップすると一覧ページを開く。
    func addAttribution(to mapView: MKMapView) {
        var configuration = UIButton.Configuration.plain()
        configuration.title = "地理院タイル"
        configuration.baseForegroundColor = .secondaryLabel
        configuration.background.backgroundColor = .systemBackground.withAlphaComponent(0.75)
        configuration.background.cornerRadius = 4
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 2, leading: 5, bottom: 2, trailing: 5
        )
        configuration.titleTextAttributesTransformer = .init { attributes in
            var updated = attributes
            updated.font = .systemFont(ofSize: 10)
            return updated
        }
        let button = UIButton(configuration: configuration)
        // 写真のときは出所が長くなるので、折り返して画面に収める。
        button.titleLabel?.numberOfLines = 0
        button.addAction(
            UIAction { _ in
                guard let url = URL(string: "https://maps.gsi.go.jp/development/ichiran.html") else {
                    return
                }
                UIApplication.shared.open(url)
            },
            for: .touchUpInside
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tag = Self.attributionTag
        mapView.addSubview(button)
        let bottom = button.bottomAnchor.constraint(
            equalTo: mapView.safeAreaLayoutGuide.bottomAnchor,
            constant: -8
        )
        bottom.identifier = Self.attributionBottomID
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.leadingAnchor,
                                            constant: 8),
            button.trailingAnchor.constraint(
                lessThanOrEqualTo: mapView.safeAreaLayoutGuide.trailingAnchor,
                constant: -60
            ),
            bottom
        ])
    }

    static let attributionTag = 7301
    static let attributionBottomID = "attribution.bottom"

    /// 下部のパネルぶんだけ出典を持ち上げ直し、タイルの種類に応じた出所に書き換える。
    func updateAttribution(on mapView: MKMapView) {
        if let button = mapView.viewWithTag(Self.attributionTag) as? UIButton {
            let title = tile.extraAttribution.map { "地理院タイル\n\($0)" } ?? "地理院タイル"
            if button.configuration?.title != title {
                button.configuration?.title = title
            }
        }
        guard let constraint = mapView.constraints.first(
            where: { $0.identifier == Self.attributionBottomID }
        ) else { return }
        constraint.constant = -8 - attributionBottomInset
    }
}
