import MapboxCoreNavigation
import MapboxDirections
import MapboxNavigation
import MapboxMaps
import Foundation
import UIKit

extension UIView {
    var parentViewController: UIViewController? {
        var parentResponder: UIResponder? = self
        while parentResponder != nil {
            parentResponder = parentResponder!.next
            if let viewController = parentResponder as? UIViewController {
                return viewController
            }
        }
        return nil
    }
}

class MapboxNavigationView: UIView {
    weak var navViewController: NavigationViewController?
    internal var mapView: MapView!
    internal var cameraLocationConsumer: CameraLocationConsumer!
    private var lineAnnotationManager: PolylineAnnotationManager?
    private var pointAnnotationManager: PointAnnotationManager?
    private var navigationService: MapboxNavigationService?
    
    @objc var origin: NSArray = [] {
        didSet { setNeedsLayout() }
    }
    
    @objc var camera: NSDictionary = [:] {
        didSet { setNeedsLayout() }
    }
    
    @objc var destination: NSArray? = [] {
        didSet {
            if(destination?.compactMap({ $0 }).count != 2) {
                stopNavigation()
            }
            setNeedsLayout()
        }
    }
    
    @objc var markers: NSArray = [] {
        didSet { setNeedsLayout() }
    }
    
    @objc var polylines: [NSDictionary] = [] {
        didSet { setNeedsLayout() }
    }
    @objc var showUserLocation: Bool = false {
        didSet { setNeedsLayout() }
    }
    @objc var followUser: Bool = false {
        didSet {
            updateUserFollowing()
        }
    }
    
    @objc var shouldSimulateRoute: Bool = false
    @objc var styleURL: NSString = ""
    @objc var mapToken: NSString = ""
    @objc var transportMode: NSString = "bike"
    @objc var navigationToken: NSString = ""
    @objc var showsEndOfRouteFeedback: Bool = false
    @objc var destinationMarker: NSDictionary?
    @objc var userLocatorMap: NSDictionary?
    @objc var userLocatorNavigation: NSDictionary?
    @objc var onLocationChange: RCTDirectEventBlock?
    @objc var onRouteProgressChange: RCTDirectEventBlock?
    @objc var onError: RCTDirectEventBlock?
    @objc var onCancelNavigation: RCTDirectEventBlock?
    @objc var onArrive: RCTDirectEventBlock?
    @objc var onNavigationStarted: RCTDirectEventBlock?
    @objc var onTap: RCTDirectEventBlock?
    @objc var onReroute: RCTDirectEventBlock?
    
    var navigating: Bool = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()

        renderMap()
        
        navViewController?.view.frame = bounds
    }
    
    override func removeFromSuperview() {
        super.removeFromSuperview()
        // cleanup and teardown any existing resources
        self.navViewController?.removeFromParent()
    }
    
    private func renderMap() {
        if(mapView == nil) {
            let myMapInitOptions = MapInitOptions()
            
            ResourceOptionsManager.default.resourceOptions.accessToken = mapToken as String
            UserDefaults.standard.setValue(self.mapToken, forKey: "MBXAccessToken")
            
            mapView = MapView(frame: bounds, mapInitOptions: myMapInitOptions)
            
            hideMapInfo(mapView)
            addGestureListener(mapView)
            
            // Add the map.
            self.addSubview(mapView)
        }

        if showUserLocation {
            if userLocatorMap != nil {
                var puck2DConfiguration = Puck2DConfiguration()
                
                puck2DConfiguration.topImage = getImage(image: userLocatorMap!)
                puck2DConfiguration.scale = .constant(1.0)
                 
                mapView.location.options.puckType = .puck2D(puck2DConfiguration)
            } else {
                mapView.location.options.puckType = .puck2D()
            }
            mapView.location.options.distanceFilter = 1
        }
        if styleURL != "" , let styleUri = URL(string: styleURL as String) {
            mapView.mapboxMap.loadStyleURI(StyleURI.init(url: styleUri)!)
        }
        
        cameraLocationConsumer = CameraLocationConsumer(mapView: mapView)
        
        self.addPolylines()
        self.addPoints()
        
        if(markers.count == 0 && polylines.count == 0) {
            self.setCamera()
        }
    }
    
    func addGestureListener(_ mv: MapView!) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        mv.isUserInteractionEnabled = true
        mv.addGestureRecognizer(tap)
    }
    
    func setCamera() {
        let center = camera.value(forKey: "center")
        if !(center is NSNull) {
            mapView.mapboxMap.setCamera(
                to: CameraOptions(
                    center: CLLocationCoordinate2D(
                        latitude: (center as! Array<Double>)[0],
                        longitude: (center as! Array<Double>)[1]
                    ),
                    zoom: camera["zoom"] as? CGFloat,
                    pitch: camera["pitch"] as? CGFloat ?? 0.0
                )
            )
        }
    }
    
    func updateUserFollowing() {
        guard mapView != nil else { return }
        
        if (followUser) {
            mapView.location.addLocationConsumer(newConsumer: self.cameraLocationConsumer)
        } else {
            mapView.location.removeLocationConsumer(consumer: self.cameraLocationConsumer)
        }
    }
    
    func addPolylines() {
        var polylinePoints: [CLLocationCoordinate2D] = []
        
        if(self.lineAnnotationManager != nil) {
            mapView.annotations.removeAnnotationManager(withId: self.lineAnnotationManager!.id)
        }
        
        let lineAnnotationManager = mapView.annotations.makePolylineAnnotationManager()
        
        if (polylines.count == 0){
            lineAnnotationManager.annotations = []
        } else {
            var polylineAnnotations: [PolylineAnnotation] = []
            for polyline in polylines {
                let coordinates: [[CLLocationDegrees]] = (polyline.value(forKey: "coordinates") ?? []) as! [[CLLocationDegrees]]
                let color = (polyline.value(forKey: "color") ?? "#00AA8D") as! String
                let opacity = (polyline.value(forKey: "opacity") ?? 1.0) as! Double
                
                var lineCoordinates: [CLLocationCoordinate2D] = []
                for coords in coordinates {
                    let point = CLLocationCoordinate2DMake(coords[0], coords[1])
                    lineCoordinates.append(point)
                    polylinePoints.append(point)
                }
                
                var polylineAnnotation = PolylineAnnotation(lineCoordinates: lineCoordinates)
                polylineAnnotation.lineColor = StyleColor(hexStringToUIColor(hex: color))
                polylineAnnotation.lineOpacity = opacity
                polylineAnnotation.lineWidth = 4.0
                
                polylineAnnotations.append(polylineAnnotation)
            }
            
            lineAnnotationManager.annotations = polylineAnnotations
        }
        
        self.lineAnnotationManager = lineAnnotationManager
        
        updateCameraForAnnotations()
    }
    
    func addPoints() {
        var pointAnnotations: [PointAnnotation] = []
        
        if(self.pointAnnotationManager != nil) {
            mapView.annotations.removeAnnotationManager(withId: self.pointAnnotationManager!.id)
        }
        
        if (markers.count > 0) {
            for (index, m) in markers.enumerated() {
                if let marker = m as? Dictionary<String, Any> {
                    let coordinates = CLLocationCoordinate2DMake(marker["latitude"]! as! CLLocationDegrees, marker["longitude"]! as! CLLocationDegrees)
                    var pointAnnotation = PointAnnotation(coordinate: coordinates)
                    
                    pointAnnotation.image = PointAnnotation.Image(image: getImage(image: marker["image"] as! NSDictionary), name: "marker" + String(index))
                    
                    pointAnnotations.append(pointAnnotation)
                }
            }
        }
        
        let pointAnnotationManager = mapView.annotations.makePointAnnotationManager()
        pointAnnotationManager.annotations = pointAnnotations

        self.pointAnnotationManager = pointAnnotationManager
        
        updateCameraForAnnotations()
    }
    
    func updateCameraForAnnotations() {
        guard navigating == false else { return }
        
        var pointsCoordinates: [CLLocationCoordinate2D] = []

        if(markers.count > 0) {
            for (index, m) in markers.enumerated() {
                if let marker = m as? Dictionary<String, Any> {
                    let coordinates = CLLocationCoordinate2DMake(marker["latitude"]! as! CLLocationDegrees, marker["longitude"]! as! CLLocationDegrees)
                    
                    pointsCoordinates.append(coordinates)
                
                }
            }
        }
        
        if (polylines.count > 0){
            for polyline in polylines {
                let coordinates: [[CLLocationDegrees]] = (polyline.value(forKey: "coordinates") ?? []) as! [[CLLocationDegrees]]
                
                for coords in coordinates {
                    let point = CLLocationCoordinate2DMake(coords[0], coords[1])
                    pointsCoordinates.append(point)
                }
            }
        }
        
        guard pointsCoordinates.count > 0 else {
            setCamera()
            return
        }
        
        let mapCamera = mapView.mapboxMap.camera(for: pointsCoordinates,
                                                         padding: .init(top: (camera["offset"] as? Bool == true) ? 82 : 42, left: 32, bottom:  (camera["offset"] as? Bool == true) ? 168 : 62, right: 32),
                                              bearing: nil,
                                              pitch: camera["pitch"] as? CGFloat ?? 1)
        mapView.camera.ease(to: mapCamera, duration: 0.5)
    }
    
    @objc func handleTap(_ sender: UITapGestureRecognizer? = nil) {
        onTap?(["message": ""]);
    }
    
    func startNavigation() {
        guard origin.compactMap({ $0 }).count == 2 && !(origin[0] is NSNull) && !(origin[1] is NSNull) else { return }
        
        if destination?.compactMap({ $0 }).count == 2 {
            
            let originWaypoint = Waypoint(coordinate: CLLocationCoordinate2D(latitude: CLLocationDegrees(origin[0] as! CGFloat), longitude: CLLocationDegrees(origin[1] as! CGFloat)))
            let destinationWaypoint = Waypoint(coordinate: CLLocationCoordinate2D(latitude: CLLocationDegrees(destination?[0] as! CGFloat), longitude: CLLocationDegrees(destination?[1] as! CGFloat)))
            
            let options = NavigationRouteOptions(waypoints: [originWaypoint, destinationWaypoint])
            //options.profileIdentifier = getTransportMode(transportMode: transportMode)
            
            UserDefaults.standard.setValue(self.navigationToken, forKey: "MBXAccessToken")
            
            Directions.shared.calculate(options) { [weak self] (session, result) in
                guard let strongSelf = self, let parentVC = strongSelf.parentViewController else {
                    return
                }
                
                switch result {
                case .failure(let error):
                    print(error.localizedDescription)
                    strongSelf.onError!(["message": error.localizedDescription])
                case .success(let response):
                    guard response.routes!.count > 0 else {
                        return
                    }
                    
                    strongSelf.navigationService = MapboxNavigationService(routeResponse: response,
                                                                    routeIndex: 0,
                                                                    routeOptions: options,
                                                                    simulating: strongSelf.shouldSimulateRoute ? .always : .never)
                    strongSelf.navigationService!.simulationSpeedMultiplier = 5
                    
                    let navigationOptions = NavigationOptions(navigationService: strongSelf.navigationService!)
                    navigationOptions.navigationService = strongSelf.navigationService!
                    navigationOptions.bottomBanner = MapboxNavigationBannerView()
                    navigationOptions.topBanner = MapboxNavigationBannerView()
                    
                    let navigationViewController = NavigationViewController(for: response, routeIndex: 0,
                                                                            routeOptions: options,
                                                                            navigationOptions: navigationOptions)
                    
                    if let mapView = navigationViewController.navigationMapView?.mapView {
                        let customViewportDataSource = MapboxNavigationViewportDataSource(mapView)
                        navigationViewController.navigationMapView?.navigationCamera.viewportDataSource = customViewportDataSource
            
                        let customCameraStateTransition = MapboxNavigationCameraStateTransition(mapView)
                        navigationViewController.navigationMapView?.navigationCamera.cameraStateTransition = customCameraStateTransition
                    }
                
                    if strongSelf.styleURL != "" , let styleUri = URL(string: strongSelf.styleURL as String) {
                        strongSelf.mapView.mapboxMap.loadStyleURI(StyleURI.init(url: styleUri)!)
                    }
                    
                    if strongSelf.userLocatorNavigation != nil {
                        var puck2DConfiguration = Puck2DConfiguration()
                    
                        puck2DConfiguration.topImage = getImage(image: (strongSelf.userLocatorNavigation)!)
                        puck2DConfiguration.scale = .constant(1.0)
                    
                        let userLocationStyle = UserLocationStyle.puck2D(configuration: puck2DConfiguration)
                    
                        navigationViewController.navigationMapView?.userLocationStyle = userLocationStyle
                    }
                    
                    if strongSelf.styleURL != "" , let styleUri = URL(string: strongSelf.styleURL as String) {
                        navigationViewController.navigationMapView?.mapView.mapboxMap.loadStyleURI(StyleURI.init(url: styleUri)!)
                    }
                    WayNameLabel.appearance().normalTextColor = UIColor.clear
                    WayNameView.appearance().backgroundColor = UIColor.clear
                    WayNameView.appearance().borderColor = UIColor.clear
                    
                    navigationViewController.routeLineTracksTraversal = true
                    navigationViewController.navigationMapView?.routeCasingColor = #colorLiteral(red: 0.2078881264, green: 0.6503844261, blue: 0.5409962535, alpha: 1)
                    navigationViewController.navigationMapView?.traversedRouteColor = UIColor.clear
                    
                    navigationViewController.navigationMapView?.trafficLowColor = UIColor.clear
                    navigationViewController.navigationMapView?.trafficHeavyColor = UIColor.clear
                    navigationViewController.navigationMapView?.trafficSevereColor = UIColor.clear
                    navigationViewController.navigationMapView?.trafficUnknownColor = UIColor.clear
                    navigationViewController.navigationMapView?.trafficModerateColor = UIColor.clear
                    navigationViewController.navigationMapView?.alternativeTrafficLowColor = UIColor.clear
                    navigationViewController.navigationMapView?.alternativeTrafficHeavyColor = UIColor.clear
                    navigationViewController.navigationMapView?.alternativeTrafficSevereColor = UIColor.clear
                    navigationViewController.navigationMapView?.alternativeTrafficUnknownColor = UIColor.clear
                    navigationViewController.navigationMapView?.alternativeTrafficModerateColor = UIColor.clear
                    
                    navigationViewController.showsEndOfRouteFeedback = strongSelf.showsEndOfRouteFeedback
                    navigationViewController.floatingButtons = []
                    navigationViewController.showsReportFeedback = false
                    navigationViewController.showsSpeedLimits = false
                    navigationViewController.delegate = strongSelf
                    
                    
                    hideMapInfo(navigationViewController.navigationMapView?.mapView)
                    strongSelf.addGestureListener(navigationViewController.navigationMapView?.mapView)
                    
                    navigationViewController.view.frame = strongSelf.bounds
                    parentVC.addChild(navigationViewController)
                    strongSelf.addSubview(navigationViewController.view)
                    navigationViewController.didMove(toParent: parentVC)
                    
                }
            }
        }
    }
    
    func stopNavigation() {
        DispatchQueue.main.async {
            self.navigationService?.stop()
            self.navViewController?.didTapCancel("stop")
            self.mapView = nil
            self.setNeedsLayout()
        }
    }
    
    func startTracking() {
        navigating = true
    }
    
    func stopTracking() {
        navigating = false
    }
    
}

public class CameraLocationConsumer: LocationConsumer {
    weak var mapView: MapView?
 
    init(mapView: MapView) {
        self.mapView = mapView
    }
     
    public func locationUpdate(newLocation: Location) {
        mapView?.camera.ease(
            to: CameraOptions(center: newLocation.coordinate, zoom: 15, bearing: newLocation.headingDirection),
            duration: 1.3
        )
    }
}
