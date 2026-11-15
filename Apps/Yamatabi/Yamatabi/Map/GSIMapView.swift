import MapKit
import SwiftUI

/// 地理院タイルを表示する地図。
///
/// SwiftUI の `Map` は独自タイルを扱えないため、UIKit の `MKMapView` を
/// `UIViewRepresentable` で包んで SwiftUI から使えるようにしています。
struct GSIMapView: UIViewRepresentable {
    /// 表示するタイルの種類。切り替えると地図が差し替わります。
    var tile: GSITile
    /// 地図に立てるピン。
    var annotations: [MountainAnnotation] = []
    /// この山にカメラを寄せる。nil なら日本全体のまま。
    var focused: Mountain?
    /// ピンがタップされたときに呼ばれる。
    var onSelect: ((MountainAnnotation) -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.showsCompass = true
        mapView.region = .japan
        context.coordinator.apply(tile: tile, to: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onSelect = onSelect

        // タイル種別が変わったときだけ、オーバーレイを張り替える。
        if context.coordinator.currentTile != tile {
            context.coordinator.apply(tile: tile, to: mapView)
        }

        // ピンの内容が変わったときだけ、差し替える。
        let newIDs = Set(annotations.map(\.mountain.id))
        if context.coordinator.currentAnnotationIDs != newIDs {
            mapView.removeAnnotations(mapView.annotations)
            mapView.addAnnotations(annotations)
            context.coordinator.currentAnnotationIDs = newIDs
        }

        // 選ばれた山が変わったら、そこへカメラを寄せる。
        if let focused, context.coordinator.focusedID != focused.id {
            let region = MKCoordinateRegion(
                center: focused.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
            mapView.setRegion(region, animated: true)
            context.coordinator.focusedID = focused.id
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// MKMapView からの通知を受け取る係。
    final class Coordinator: NSObject, MKMapViewDelegate {
        private(set) var currentTile: GSITile?
        private var overlay: MKTileOverlay?
        var currentAnnotationIDs: Set<String> = []
        var focusedID: String?
        var onSelect: ((MountainAnnotation) -> Void)?

        func apply(tile: GSITile, to mapView: MKMapView) {
            if let overlay {
                mapView.removeOverlay(overlay)
            }
            let newOverlay = tile.makeOverlay()
            mapView.addOverlay(newOverlay, level: .aboveLabels)
            overlay = newOverlay
            currentTile = tile
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tileOverlay = overlay as? MKTileOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            return MKTileOverlayRenderer(tileOverlay: tileOverlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let mountain = annotation as? MountainAnnotation else { return nil }

            let identifier = "mountain"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: mountain, reuseIdentifier: identifier)

            view.annotation = mountain
            view.canShowCallout = true
            view.markerTintColor = .systemGreen
            view.glyphImage = UIImage(systemName: "mountain.2.fill")
            view.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            return view
        }

        func mapView(
            _ mapView: MKMapView,
            annotationView view: MKAnnotationView,
            calloutAccessoryControlTapped control: UIControl
        ) {
            guard let mountain = view.annotation as? MountainAnnotation else { return }
            onSelect?(mountain)
        }
    }
}

extension MKCoordinateRegion {
    /// 日本全体がちょうど収まる範囲。
    static let japan = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5, longitude: 137.5),
        span: MKCoordinateSpan(latitudeDelta: 16.0, longitudeDelta: 16.0)
    )
}
