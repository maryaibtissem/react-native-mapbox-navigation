package com.homee.mapboxnavigation

import android.annotation.SuppressLint
import android.graphics.Color
import android.widget.LinearLayout
import com.facebook.react.uimanager.ThemedReactContext
import com.mapbox.geojson.Point
import com.mapbox.maps.plugin.LocationPuck2D
import com.mapbox.maps.plugin.locationcomponent.location
import android.graphics.drawable.Drawable
import com.mapbox.maps.plugin.compass.compass
import java.net.URL
import android.os.AsyncTask
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.facebook.react.bridge.*
import com.mapbox.maps.*
import com.mapbox.maps.plugin.annotation.annotations
import com.mapbox.maps.plugin.annotation.generated.*
import com.mapbox.maps.plugin.attribution.attribution
import com.mapbox.maps.plugin.logo.logo
import com.mapbox.maps.plugin.scalebar.scalebar
import com.mapbox.navigation.ui.utils.internal.extensions.getBitmap

class MapboxNavigationView(private val context: ThemedReactContext, private val mCallerContext: ReactApplicationContext): LinearLayout(context.baseContext) {
    private var origin: Point? = null
    private var destination: Point? = null
    private var shouldSimulateRoute = false
    private var showsEndOfRouteFeedback = false
    private var mapToken: String? = null
    private var navigationToken: String? = null
    private var camera: ReadableMap? = null
    private var destinationMarker: Drawable? = null
    private var userLocatorMap: Drawable? = null
    private var userLocatorNavigation: Drawable? = null
    private var styleURL: String? = null
    private var transportMode: String = "bike"
    private var showUserLocation = false
    private var markers: ReadableArray? = null
    private var polylines: ReadableArray? = null

    var mapboxMap: MapboxMap? = null
    private var mapView: MapView? = null
    private var mapboxNavView: MapboxNavigationNavView? = null

    private var isNavigation = false
    private var polylineAnnotationManager: PolylineAnnotationManager? = null
    private var polylineAnnotation: PolylineAnnotation? = null
    private var pointAnnotation: PointAnnotation? = null
    private var pointAnnotationManager: PointAnnotationManager? = null

    companion object {
        var instance: MapboxNavigationView? = null
    }

    init {
        createMap()
        instance = this
    }

    private fun createMap() {
        mCallerContext.runOnUiQueueThread {
            ResourceOptionsManager.getDefault(context.baseContext, mapToken!!)

            val mapboxMapView = MapboxNavigationMapView(context, this, id)
            mapView = mapboxMapView.initMap()

            mapView?.let { mapView ->
                mapboxMap = mapView.getMapboxMap()

                mapView.logo?.marginLeft = 3000.0F
                mapView.compass?.enabled = false
                mapView.attribution?.iconColor = Color.TRANSPARENT
                mapView.scalebar?.enabled = false

                val annotationApi = mapView.annotations

                polylineAnnotationManager = annotationApi?.createPolylineAnnotationManager(mapView)
                pointAnnotationManager = annotationApi?.createPointAnnotationManager(mapView)
            }
        }
    }

    private fun updateMap() {
        if (styleURL != null) {
            mapboxMap?.loadStyleUri(styleURL!!) {
                customizeMap()
            }
        } else {
            customizeMap()
        }
    }

    private fun customizeMap() {
        if (showUserLocation) {
            mapView?.location?.updateSettings {
                enabled = true
                pulsingEnabled = false
            }
        }

        if (userLocatorMap != null) {
            mapView?.location?.locationPuck = LocationPuck2D(
                topImage = userLocatorMap,
            )
        }

        if (!isNavigation) {
            addMarkers()
            addPolylines()
            fitCameraForAnnotations()
        }
    }

    fun fitCameraForAnnotations() {
        val points = mutableListOf<Point>()

        // add polylines points
        if (polylines != null) {
            for (i in 0 until polylines!!.size()) {
                val polylineInfo = polylines!!.getMap(i)
                val polyline = polylineInfo!!.getArray("coordinates")

                for (j in 0 until polyline!!.size()) {
                    val polylineArr = polyline!!.getArray(j)!!
                    val lat = polylineArr.getDouble(0)
                    val lng = polylineArr.getDouble(1)
                    val point = Point.fromLngLat(lng, lat)

                    points.add(point)
                }
            }
        }

        // add markers points
        if (markers != null) {
            for (i in 0 until markers!!.size()) {
                val marker = markers!!.getMap(i)

                if (marker != null) {
                    val markerLatitude = marker.getDouble("latitude")!!
                    val markerLongitude = marker.getDouble("longitude")!!
                    val point = Point.fromLngLat(markerLongitude, markerLatitude)

                    points.add(point)
                }
            }
        }

        if (points.size > 0) {
            val newCameraOptions = mapboxMap!!.cameraForCoordinates(
                points,
                EdgeInsets(
                    if (camera!!.hasKey("offset") && camera!!.getBoolean("offset")) 62.0 else 42.0,
                    72.0,
                    if (camera!!.hasKey("offset") && camera!!.getBoolean("offset")) 328.0 else 32.0,
                    72.0
                ))
            mapboxMap?.setCamera(newCameraOptions)
        } else {
            updateCamera()
        }
    }

    fun updateCamera() {
        if (camera != null) {
            val center = try {
                Point.fromLngLat(
                    camera!!.getArray("center")!!.getDouble(1),
                    camera!!.getArray("center")!!.getDouble(0)
                )
            } catch (e: Exception) {
                mapboxMap?.cameraState?.center
            }

            val zoom = try {
                camera!!.getDouble("zoom")
            } catch (e: Exception) {
                15.0
            }

            val pitch = try {
                camera!!.getDouble("pitch")
            } catch (e: Exception) {
                0.0
            }

            val cameraOptions = CameraOptions.Builder()
                .center(center)
                .zoom(zoom)
                .pitch(pitch)
                .build()

            mapboxMap?.setCamera(cameraOptions)
        }
    }

    fun startNavigation() {
        if (navigationToken != null
            && destination != null
            && mapView != null) {
            isNavigation = true

            mapboxNavView = MapboxNavigationNavView(context, navigationToken!!, id, mapView!!)
            mapboxNavView!!.initNavigation(userLocatorNavigation)
            mapboxNavView!!.shouldSimulateRoute = shouldSimulateRoute
            mapboxNavView!!.startNavigation(mapView!!, origin!!, destination!!, transportMode)
        }
    }

    fun stopNavigation() {
        if (isNavigation && mapboxNavView != null) {
            isNavigation = false

            mapboxNavView!!.stopNavigation(camera)
        }
    }

    private fun addPolylines() {
        Handler(Looper.getMainLooper()).post {
            if (mapView != null) {
                if (polylines != null && polylineAnnotationManager != null && polylines!!.size() > 0) {
                    for (i in 0 until polylines!!.size()) {
                        val coordinates = mutableListOf<Point>()
                        val polylineInfo = polylines!!.getMap(i)
                        val polyline = polylineInfo!!.getArray("coordinates")
                        val color = polylineInfo!!.getString("color")
                        val opacity =
                            if (polylineInfo!!.hasKey("opacity")) polylineInfo!!.getDouble("opacity") else 1.0

                        for (j in 0 until polyline!!.size()) {
                            val polylineArr = polyline!!.getArray(j)!!
                            val lat = polylineArr.getDouble(0)
                            val lng = polylineArr.getDouble(1)
                            val point = Point.fromLngLat(lng, lat)

                            coordinates.add(point)
                        }

                        val polylineAnnotationOptions = PolylineAnnotationOptions()
                            .withPoints(coordinates)
                            .withLineColor(color ?: "#00AA8D")
                            .withLineWidth(5.0)
                            .withLineOpacity(opacity)
                        polylineAnnotation =
                            polylineAnnotationManager!!.create(polylineAnnotationOptions)

                    }
                } else {
                    if (polylineAnnotation != null) {
                        polylineAnnotationManager?.deleteAll()
                        polylineAnnotation = null
                    }
                }
            }
        }
    }

    private fun addMarkers() {
        Handler(Looper.getMainLooper()).post {
            if (mapView != null) {
                if (markers != null && markers!!.size() > 0) {
                    doAsync {
                        for (i in 0 until markers!!.size()) {
                            val marker = markers!!.getMap(i)

                            if (marker != null) {
                                val markerLatitude = marker.getDouble("latitude")!!
                                val markerLongitude = marker.getDouble("longitude")!!

                                val markerIcon = marker.getMap("image")!!
                                val markerUrl = markerIcon.getString("uri")
                                val icon = getDrawableFromUri(markerUrl)
                                val point = Point.fromLngLat(markerLongitude, markerLatitude)
                                val pointAnnotationOptions: PointAnnotationOptions =
                                    PointAnnotationOptions()
                                        .withPoint(point)

                                if (icon !== null) {
                                    pointAnnotationOptions.withIconImage(icon.getBitmap())
                                }

                                pointAnnotation =
                                    pointAnnotationManager?.create(pointAnnotationOptions)
                            }
                        }
                    }
                } else {
                    if (pointAnnotation != null) {
                        pointAnnotationManager?.deleteAll()
                        pointAnnotation = null
                    }
                }
            }
        }
    }

    fun setOrigin(origin: Point?) {
        this.origin = origin
    }

    fun setDestination(destination: Point?) {
        this.destination = destination
    }

    fun setShouldSimulateRoute(shouldSimulateRoute: Boolean) {
        this.shouldSimulateRoute = shouldSimulateRoute
    }

    fun setShowsEndOfRouteFeedback(showsEndOfRouteFeedback: Boolean) {
        this.showsEndOfRouteFeedback = showsEndOfRouteFeedback
    }

    fun setMapToken(mapToken: String) {
        this.mapToken = mapToken
        updateMap()
    }

    fun setTransportMode(transportMode: String?) {
        if(transportMode != null) {
            this.transportMode = transportMode
        }
    }

    fun setNavigationToken(navigationToken: String) {
        this.navigationToken = navigationToken
    }

    fun setCamera(camera: ReadableMap) {
        val offset = if(camera.hasKey("offset"))
            camera.getBoolean("offset")
        else
            if(this.camera != null && this.camera!!.hasKey("offset"))
                this.camera!!.getBoolean("offset")
            else
                false
        val center = if(camera.hasKey("center"))
            camera.getArray("center")
        else
            if(this.camera != null && this.camera!!.hasKey("center"))
                this.camera!!.getArray("center")
            else
                null
        val zoom = if(camera.hasKey("zoom"))
            camera.getDouble("zoom")
        else
            if(this.camera != null && this.camera!!.hasKey("zoom"))
                this.camera!!.getDouble("zoom")
            else
                null
        val pitch = if(camera.hasKey("pitch"))
            camera.getDouble("pitch")
        else
            if(this.camera != null && this.camera!!.hasKey("pitch"))
                this.camera!!.getDouble("pitch")
            else
                null

        val newCamera = Arguments.createMap()
        if (center != null) {
            val centerWritableArray = Arguments.createArray()
            centerWritableArray.pushDouble(center.getDouble(0))
            centerWritableArray.pushDouble(center.getDouble(1))
            newCamera.putArray("center", centerWritableArray)
        }
        if (zoom != null) newCamera.putDouble("zoom", zoom)
        if (pitch != null) newCamera.putDouble("pitch", pitch)
        newCamera.putBoolean("offset", offset)

        this.camera = newCamera

        updateCamera()
    }

    fun setDestinationMarker(destinationMarker: ReadableMap) {
        doAsync {
            val imageUrl = destinationMarker?.getString("uri")
            val drawable: Drawable? = getDrawableFromUri(imageUrl)
            this.destinationMarker = drawable
            updateMap()
        }
    }

    fun setUserLocatorMap(userLocatorMap: ReadableMap) {
        doAsync {
            val imageUrl = userLocatorMap?.getString("uri")
            val drawable: Drawable? = getDrawableFromUri(imageUrl)
            this.userLocatorMap = drawable
            updateMap()
        }
    }

    fun setUserLocatorNavigation(userLocatorNavigation: ReadableMap) {
        doAsync {
            val imageUrl = userLocatorNavigation?.getString("uri")
            val drawable: Drawable? = getDrawableFromUri(imageUrl)
            this.userLocatorNavigation = drawable
            updateMap()
        }
    }

    fun setStyleURL(styleURL: String) {
        this.styleURL = styleURL
        updateMap()
    }

    fun setShowUserLocation(showUserLocation: Boolean) {
        this.showUserLocation = showUserLocation
        updateMap()
    }

    fun setMarkers(markers: ReadableArray?) {
        this.markers = markers
    }

    fun setPolylines(polylines: ReadableArray?) {
        this.polylines = polylines
        if (
            (this.polylines != null && this.polylines!!.size() > 0) ||
            (this.markers != null && this.markers!!.size() > 0)
        ) {
            updateMap()
        }
    }

    fun onDropViewInstance() {
        mapView?.onDestroy()
    }

    private fun getDrawableFromUri(imageUrl: String?): Drawable? {
        var drawable: Drawable?
        if (imageUrl?.contains("http") == true) {
            val inputStream = URL(imageUrl).openStream()
            drawable = Drawable.createFromStream(inputStream, "src")
        } else {
            val resourceId = mCallerContext.resources.getIdentifier(
                imageUrl,
                "drawable",
                mCallerContext.packageName
            )
            drawable =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) resources.getDrawable(
                    resourceId,
                    mCallerContext.theme
                ) else resources.getDrawable(resourceId)
        }
        return drawable
    }

    @SuppressLint("NewApi")
    class doAsync(val handler: () -> Unit) : AsyncTask<Void, Void, Void>() {
        init {
            execute()
        }

        override fun doInBackground(vararg params: Void?): Void? {
            handler()
            return null
        }
    }
}
