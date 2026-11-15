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
    /// 最初に表示する中心。山を選ばずに特定地点を見せたいときに使います。
    var initialCenter: CLLocationCoordinate2D?
    /// 記録中の軌跡。地図上に線で描きます。
    var track: [TrackPoint] = []
    /// 現在地の青い点を表示するか。
    var showsUserLocation = false
    /// 軌跡の先端にカメラを追従させるか。記録中に使います。
    var followsTrack = false
    /// 軌跡の全体が画面に収まるようにカメラを合わせるか。記録の振り返りに使います。
    var fitsTrack = false
    /// ピンがタップされたときに呼ばれる。
    var onSelect: ((MountainAnnotation) -> Void)?
    /// 地図を長押ししたときに呼ばれる。登山口を自分で指定するのに使います。
    var onLongPress: ((CLLocationCoordinate2D) -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.showsCompass = true
        if let initialCenter {
            mapView.region = MKCoordinateRegion(
                center: initialCenter,
                span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
            )
        } else {
            mapView.region = .japan
        }
        context.coordinator.apply(tile: tile, to: mapView)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        mapView.addGestureRecognizer(longPress)
        context.coordinator.mapView = mapView

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.onLongPress = onLongPress

        if mapView.showsUserLocation != showsUserLocation {
            mapView.showsUserLocation = showsUserLocation
        }

        // 軌跡は点が増えるたびに描き直す。
        if context.coordinator.trackCount != track.count {
            context.coordinator.updateTrack(track, on: mapView)

            // 保存済みの記録を開いたときは、軌跡全体が収まる位置に合わせる。
            if fitsTrack, let line = context.coordinator.trackLine {
                mapView.setVisibleMapRect(
                    line.boundingMapRect,
                    edgePadding: UIEdgeInsets(top: 70, left: 50, bottom: 180, right: 50),
                    animated: false
                )
            }
        }
        // 記録中は、軌跡の先端を画面の中心に保つ。
        if followsTrack, let tip = track.last {
            if context.coordinator.hasZoomedToTrack {
                mapView.setCenter(tip.coordinate, animated: true)
            } else {
                // 最初の1回だけ、日本全体の表示から足元が見える縮尺まで寄せる。
                // 以降は縮尺を触らず、利用者が拡大・縮小した状態を尊重する。
                mapView.setRegion(
                    MKCoordinateRegion(
                        center: tip.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
                    ),
                    animated: true
                )
                context.coordinator.hasZoomedToTrack = true
            }
        } else if !followsTrack {
            context.coordinator.hasZoomedToTrack = false
        }

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
        var onLongPress: ((CLLocationCoordinate2D) -> Void)?
        weak var mapView: MKMapView?
        private(set) var trackCount = 0

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            // 押し下げた瞬間に1回だけ反応させる。離すまで待つと取りこぼしやすい。
            guard gesture.state == .began, let mapView else { return }
            let point = gesture.location(in: mapView)
            onLongPress?(mapView.convert(point, toCoordinateFrom: mapView))
        }
        /// 記録開始時のズームを1度だけ行うためのフラグ。
        var hasZoomedToTrack = false
        private(set) var trackLine: MKPolyline?

        /// 軌跡の線を引き直す。
        func updateTrack(_ track: [TrackPoint], on mapView: MKMapView) {
            if let trackLine {
                mapView.removeOverlay(trackLine)
                self.trackLine = nil
            }
            trackCount = track.count

            guard track.count >= 2 else { return }
            let coordinates = track.map(\.coordinate)
            let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
            // タイルより上、ラベルより上に重ねる。
            mapView.addOverlay(line, level: .aboveLabels)
            trackLine = line
        }

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
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                // 地理院地図は登山道が黄色〜橙、等高線が茶色。
                // それらに埋もれないよう、地図側で使われていない赤を選んでいる。
                renderer.strokeColor = UIColor.systemRed.withAlphaComponent(0.9)
                renderer.lineWidth = 5
                renderer.lineJoin = .round
                renderer.lineCap = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // 近接したピンがまとめられたもの。1,000地点あるので、
            // まとめ表示が無いと日本全体を見たときに地図が埋まってしまう。
            if let cluster = annotation as? MKClusterAnnotation {
                let identifier = "cluster"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: identifier)
                view.annotation = cluster
                view.markerTintColor = .systemGreen
                // まとめた中に百名山があれば、その数を出して目印にする。
                view.glyphText = "\(cluster.memberAnnotations.count)"
                view.displayPriority = .defaultHigh
                // まとめピンの既定の表題は「荒島岳 +その他129件」のように長く、
                // 地図の上に大きく被ってしまうので出さない。数字だけで用は足りる。
                view.titleVisibility = .hidden
                view.subtitleVisibility = .hidden
                return view
            }

            guard let mountain = annotation as? MountainAnnotation else { return nil }

            let identifier = "mountain"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: mountain, reuseIdentifier: identifier)

            view.annotation = mountain
            view.canShowCallout = true
            view.clusteringIdentifier = "mountain"
            view.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)

            // 百名山は濃い緑＋塗りつぶしのアイコンで目立たせ、
            // それ以外は控えめにして、地図の情報量を抑える。
            if mountain.mountain.isHyakumeizan {
                view.markerTintColor = .systemGreen
                view.glyphImage = UIImage(systemName: "mountain.2.fill")
                // 混み合ったときは百名山を優先して残す。
                view.displayPriority = .required
            } else {
                view.markerTintColor = .systemGray
                view.glyphImage = UIImage(systemName: "mountain.2")
                view.displayPriority = .defaultLow
            }
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

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            // まとめられたピンを押したら、中身がばらけるまで寄る。
            guard let cluster = view.annotation as? MKClusterAnnotation else { return }
            mapView.deselectAnnotation(cluster, animated: false)

            var rect = MKMapRect.null
            for member in cluster.memberAnnotations {
                let point = MKMapPoint(member.coordinate)
                rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
            }
            mapView.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: 90, left: 70, bottom: 200, right: 70),
                animated: true
            )
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
