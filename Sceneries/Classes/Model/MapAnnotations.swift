//
//  MapAnnotations.swift
//  Sceneries
//
//  Created by Paolo Manna on 28/08/2020.
//  Copyright © 2020 MongoDB. All rights reserved.
//

import MapKit
import UIKit

class PhotoViewAnnotation: MKPointAnnotation {
	var photo: PhotoView!
	var thumbnailURL: URL!
	var photoURL: URL!
	var markerColor: UIColor!
	
	convenience init(photo: PhotoView) {
		self.init()
		
		self.photo			= photo
		title			= photo.title
		subtitle		= photo.owner
		coordinate		= photo.location!.clLocation.coordinate
		thumbnailURL	= photo.thumbnailURL()
		photoURL		= photo.imageURL()
		
		switch photo.statusEnum {
		case .ToSee:
			markerColor	= .systemOrange
		case .CantMiss:
			markerColor	= .systemGreen
		case .Unworthy:
			markerColor	= .systemRed
		}
	}
	
	func annotationView() -> MKMarkerAnnotationView? {
		let annotationView	= MKMarkerAnnotationView(annotation: self, reuseIdentifier: "photoViewAnnotation")
		
		annotationView.glyphImage		= UIImage(named: "Camera")
		annotationView.markerTintColor	= markerColor
		annotationView.glyphTintColor	= .white
		
		annotationView.rightCalloutAccessoryView	= UIButton(type: .close)
		
		annotationView.canShowCallout	= true
		
		// TODO: A more complex callout view?
		let calloutView = UIImageView()
		
		// setup constraints for custom view
		calloutView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			calloutView.widthAnchor.constraint(equalToConstant: 160.0),
			calloutView.heightAnchor.constraint(equalToConstant: 75.0)
		])

		calloutView.downloadedFrom(url: thumbnailURL)
		
		annotationView.detailCalloutAccessoryView	= calloutView
		
		return annotationView
	}
}

class ViewPointAnnotation: MKPointAnnotation {
	var viewPoint: ViewPoint!

	convenience init(viewPoint: ViewPoint) {
		self.init()
		
		self.viewPoint	= viewPoint
		title		= viewPoint.name
		subtitle	= nil
		coordinate	= viewPoint.location?.clLocation.coordinate ?? CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
	}
	
	func annotationView() -> MKMarkerAnnotationView? {
		let annotationView	= MKMarkerAnnotationView(annotation: self, reuseIdentifier: "viewPointAnnotation")
		
		annotationView.glyphImage		= UIImage(named: "Camera")
		annotationView.markerTintColor	= .systemIndigo
		annotationView.glyphTintColor	= .white
				
		annotationView.rightCalloutAccessoryView	= UIButton(type: .close)

		annotationView.canShowCallout	= true
		
		return annotationView
	}
}
