//
//  ViewController.swift
//  MapboxDemo
//
//  Created by Jeremy Osterhoudt on 11/22/17.
//  Copyright © 2017 Jeremy Osterhoudt. All rights reserved.
//

import UIKit
import Mapbox

class ViewController: UIViewController {

    @IBOutlet var mapView: MGLMapView!
    var progressView: UIProgressView?
    var yosemite: MGLCoordinateBounds!
    
    deinit {
        // Remove offline pack observers.
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        mapView.setCenter(CLLocationCoordinate2D(latitude: 37.90, longitude: -119.530681), zoomLevel: 8, animated: false)
        mapView.allowsRotating = false
        
        let ne = CLLocationCoordinate2D(latitude: 38.90, longitude: -119)
        let sw = CLLocationCoordinate2D(latitude: 36.90, longitude: -120)
        yosemite = MGLCoordinateBounds(sw: sw, ne: ne)
        
        // Setup offline pack notification handlers.
        NotificationCenter.default.addObserver(self, selector: #selector(offlinePackProgressDidChange), name: NSNotification.Name.MGLOfflinePackProgressChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(offlinePackDidReceiveError), name: NSNotification.Name.MGLOfflinePackError, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(offlinePackDidReceiveMaximumAllowedMapboxTiles), name: NSNotification.Name.MGLOfflinePackMaximumMapboxTilesReached, object: nil)
    }
}

extension ViewController: MGLMapViewDelegate {
    func mapView(_ mapView: MGLMapView, shouldChangeFrom oldCamera: MGLMapCamera, to newCamera: MGLMapCamera) -> Bool {
        
        // Get the current camera to restore it after.
        let currentCamera = mapView.camera
        
        // From the new camera obtain the center to test if it’s inside the boundaries.
        let newCameraCenter = newCamera.centerCoordinate
        
        // Set the map’s visible bounds to newCamera.
        mapView.camera = newCamera
        let newVisibleCoordinates = mapView.visibleCoordinateBounds
        
        // Revert the camera.
        mapView.camera = currentCamera
        
        // Test if the newCameraCenter and newVisibleCoordinates are inside self.colorado.
        let inside = MGLCoordinateInCoordinateBounds(newCameraCenter, self.yosemite)
        let intersects = MGLCoordinateInCoordinateBounds(newVisibleCoordinates.ne, self.yosemite) && MGLCoordinateInCoordinateBounds(newVisibleCoordinates.sw, self.yosemite)
        
        return inside && intersects
    }
    
    func mapViewDidFinishLoadingMap(_ mapView: MGLMapView) {
        startOfflinePackDownload()
    }
    
    func startOfflinePackDownload() {
        let offlineStorage = MGLOfflineStorage.shared()
        guard !self.packHasBeenDownloaded(offlineStorage: offlineStorage) else {
            return
        }
        
        //create a progress indicator
        let progressbarView = UIProgressView(progressViewStyle: .default)
        progressView = progressbarView
        let frame = view.bounds.size
        progressbarView.frame = CGRect(x: frame.width / 4, y: frame.height * 0.75, width: frame.width / 2, height: 10)
        view.addSubview(progressbarView)
        
        // Create a region that includes the current viewport and any tiles needed to view it when zoomed further in.
        let region = MGLTilePyramidOfflineRegion(styleURL: mapView.styleURL, bounds: mapView.visibleCoordinateBounds, fromZoomLevel: 8, toZoomLevel: 14)
        
        // Store some data for identification purposes alongside the downloaded resources.
        let userInfo = ["name": "YosemiteOfflinePack"]
        let context = NSKeyedArchiver.archivedData(withRootObject: userInfo)
        
        // Create and register an offline pack with the shared offline storage object.
        
        MGLOfflineStorage.shared().addPack(for: region, withContext: context) { (pack, error) in
            guard error == nil else {
                // The pack couldn’t be created for some reason.
                print("Error: \(error?.localizedDescription ?? "unknown error")")
                return
            }
            
            // Start downloading.
            pack?.resume()
        }
    }
    
    private func packHasBeenDownloaded(offlineStorage: MGLOfflineStorage) -> Bool {
        if let packs = offlineStorage.packs {
            for pack in packs {
                if let context = NSKeyedUnarchiver.unarchiveObject(with: pack.context) as? [String : String] {
                    if context["name"] == "YosemiteOfflinePack" {
                        return true
                    }
                }
            }
        }
        
        return false
    }
}

//Notification handling
extension ViewController {
    // MARK: - MGLOfflinePack notification handlers
    @objc func offlinePackProgressDidChange(notification: NSNotification) {
        // Get the offline pack this notification is regarding,
        // and the associated user info for the pack; in this case, `name = My Offline Pack`
        if let pack = notification.object as? MGLOfflinePack,
            let userInfo = NSKeyedUnarchiver.unarchiveObject(with: pack.context) as? [String: String] {
            let progress = pack.progress
            let completedResources = progress.countOfResourcesCompleted
            let expectedResources = progress.countOfResourcesExpected
            
            // Calculate current progress percentage.
            let progressPercentage = Float(completedResources) / Float(expectedResources)
            progressView?.progress = progressPercentage
            
            // If this pack has finished, print its size and resource count.
            if completedResources == expectedResources {
                let byteCount = ByteCountFormatter.string(fromByteCount: Int64(pack.progress.countOfBytesCompleted), countStyle: ByteCountFormatter.CountStyle.memory)
                print("Offline pack “\(userInfo["name"] ?? "unknown")” completed: \(byteCount), \(completedResources) resources")
                progressView?.removeFromSuperview()
            } else {
                // Otherwise, print download/verification progress.
                print("Offline pack “\(userInfo["name"] ?? "unknown")” has \(completedResources) of \(expectedResources) resources — \(progressPercentage * 100)%.")
            }
        }
    }
    
    @objc func offlinePackDidReceiveError(notification: NSNotification) {
        if let pack = notification.object as? MGLOfflinePack,
            let userInfo = NSKeyedUnarchiver.unarchiveObject(with: pack.context) as? [String: String],
            let error = notification.userInfo?[MGLOfflinePackUserInfoKey.error] as? NSError {
            print("Offline pack “\(userInfo["name"] ?? "unknown")” received error: \(error.localizedFailureReason ?? "unknown error")")
        }
    }
    
    @objc func offlinePackDidReceiveMaximumAllowedMapboxTiles(notification: NSNotification) {
        if let pack = notification.object as? MGLOfflinePack,
            let userInfo = NSKeyedUnarchiver.unarchiveObject(with: pack.context) as? [String: String],
            let maximumCount = (notification.userInfo?[MGLOfflinePackUserInfoKey.maximumCount] as AnyObject).uint64Value {
            print("Offline pack “\(userInfo["name"] ?? "unknown")” reached limit of \(maximumCount) tiles.")
        }
    }
}

