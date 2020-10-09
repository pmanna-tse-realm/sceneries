//
//  JourneyMapViewController.swift
//  Sceneries
//
//  Created by Paolo Manna on 24/08/2020.
//  Copyright © 2020 MongoDB. All rights reserved.
//

import MapKit
import RealmSwift
import UIKit

enum ViewPointStatus {
	case none
	case add
	case edit
}

class JourneyMapViewController: UIViewController, Storyboarded, MKMapViewDelegate {
	weak var coordinator: MainCoordinator?
    
	var realm: Realm!
	var journey: Journey!
	var notificationToken: NotificationToken?
	var selectedViewPoint: ViewPoint?
	
	var flickrAnnotations		= [FlickrAnnotation]()
	var viewPointAnnotations	= [ViewPointAnnotation]()
	var photoAnnotations		= [PhotoViewAnnotation]()

	@IBOutlet var mapView: MKMapView!
	@IBOutlet var imagesButton: UIButton!
	@IBOutlet var addViewPointButton: UIButton!
	@IBOutlet var detailImageView: UIImageView!

	override func viewDidLoad() {
		super.viewDidLoad()

		// Do any additional setup after loading the view.
		title	= journey.name
		
		imagesButton.isHidden	= true
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		
		if settings.locationEnabled, mapView.showsUserLocation {
			let userCoordinate	= mapView.userLocation.coordinate
			
			// Sometimes we can get in here with no coordinates yet
			if userCoordinate.latitude != 0.0 || userCoordinate.longitude != 0.0 {
				let mapRegion		= MKCoordinateRegion(center: userCoordinate, latitudinalMeters: 10000, longitudinalMeters: 10000)
				
				mapView.setRegion(mapRegion, animated: true)
			}
		}
		
		notificationToken = journey.observe { [weak self] change in
			guard let nav = self?.navigationController as? NavigationControllerWithError,
				let mapView = self?.mapView else { return }
			
			switch change {
			case let .change(_, changes):
				for aChange in changes {
					print("\(aChange.name): \(String(describing: aChange.oldValue)) -> \(String(describing: aChange.newValue))")
				}
			case .deleted:
				break
			case let .error(error):
				// An error occurred while opening the Realm file on the background worker thread
				nav.postErrorMessage(message: error.localizedDescription, isError: true)
			}
		}
		
		rebuildMap()
	}
	
	// MARK: - Actions
	
	func rebuildMap() {
		mapView.removeAnnotations(viewPointAnnotations)
		viewPointAnnotations.removeAll()
		
		mapView.removeAnnotations(photoAnnotations)
		photoAnnotations.removeAll()
		
		for viewPoint in journey.viewPoints {
			viewPointAnnotations.append(ViewPointAnnotation(viewPoint: viewPoint))
		}
		
		mapView.addAnnotations(viewPointAnnotations)
	}
	
	func buildFlickrAnnotations(with photos: [FlickrPhoto]) {
		mapView.removeAnnotations(flickrAnnotations)
		
		flickrAnnotations.removeAll()
		
		for aPhoto in photos {
			guard aPhoto.location != nil else { continue }
			
			// Don't add a photo we're already tracking
			// Is there a better way to do this? Perhaps with predicates?
			var found	= false
			/*
			 for jPoint in journey.viewPoints {
			 	if found { continue }
				
			 	for vPhoto in jPoint.photos {
			 		if aPhoto.imageId == vPhoto.imageId {
			 			found = true
			 			break
			 		}
			 	}
			 }
			 */
			if !found { flickrAnnotations.append(FlickrAnnotation(photo: aPhoto)) }
		}
		
		mapView.addAnnotations(flickrAnnotations)
		
		mapView.setNeedsDisplay()
	}
	
	@IBAction func fetchImagesAroundMe(_ sender: UIButton) {
		guard let viewPoint = selectedViewPoint, let location = viewPoint.location else { return }
		
		let centerCoords = location.clLocation.coordinate
		
		flickrService.picturesAround(latitude: centerCoords.latitude, longitude: centerCoords.longitude, radius: 5.0) { error, photoArray in
			guard let photos = photoArray else {
				// TODO: Show error
				if let errDesc = error?.localizedDescription {
					DispatchQueue.main.async { [weak self] in
						(self?.navigationController as? NavigationControllerWithError)?.postErrorMessage(message: errDesc, isError: true)
					}
				}
				return
			}
			
			DispatchQueue.main.async { [weak self] in
				self?.buildFlickrAnnotations(with: photos)
			}
		}
	}
	
	@IBAction func addViewPoint(_ sender: UIButton) {
		let centerCoords	= mapView.centerCoordinate
		let alertController = UIAlertController(title: "Add View Point", message: "", preferredStyle: .alert)

		alertController.addAction(UIAlertAction(title: "Add", style: .default, handler: { [weak self] _ -> Void in
			guard let self = self else { return }
			
			let textField = alertController.textFields![0] as UITextField
			let viewPoint = ViewPoint(name: textField.text ?? "ViewPoint \(self.journey.viewPoints.count + 1)",
			                          location: CLLocation(latitude: centerCoords.latitude, longitude: centerCoords.longitude))

			try! self.realm.write {
				self.journey.viewPoints.append(viewPoint)
			}
			
			let vpAnnotation	= ViewPointAnnotation(viewPoint: viewPoint)
			
			self.viewPointAnnotations.append(vpAnnotation)
			self.mapView.addAnnotation(vpAnnotation)
		}))
		alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		alertController.addTextField(configurationHandler: { (textField: UITextField!) -> Void in
			textField.placeholder = "New ViewPoint Name"
		})
		present(alertController, animated: true, completion: nil)
	}
	
	// MARK: - MKMapViewDelegate
	
	func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
		switch annotation {
		case is MKUserLocation:
			return nil
		case is FlickrAnnotation:
			return (annotation as? FlickrAnnotation)?.annotationView()
		case is  ViewPointAnnotation:
			return (annotation as? ViewPointAnnotation)?.annotationView()
		case is PhotoViewAnnotation:
			// TODO: ?
			break
		default:
			break
		}
		
		return nil
	}
	
	func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
		let annotation	= view.annotation
		
		switch annotation {
		case is MKUserLocation:
			return
		case is FlickrAnnotation:
			// TODO: ?
			break
		case is  ViewPointAnnotation:
			// TODO: ?
			break
		case is PhotoViewAnnotation:
			// TODO: ?
			break
		default:
			break
		}
	}
	
	func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
		let annotation	= view.annotation
		
		switch annotation {
		case is MKUserLocation:
			return
		case is FlickrAnnotation:
			// TODO: ?
			break
		case is  ViewPointAnnotation:
			// TODO: ?
			break
		case is PhotoViewAnnotation:
			// TODO: ?
			break
		default:
			break
		}
	}
	
	func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
		let annotation	= view.annotation
		
		switch annotation {
		case is MKUserLocation:
			return
		case is FlickrAnnotation:
			// TODO: ?
			break
		case is  ViewPointAnnotation:
			// TODO: ?
			break
		case is PhotoViewAnnotation:
			// TODO: ?
			break
		default:
			break
		}
	}
}
