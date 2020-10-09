//
//  FlickrAPIService.swift
//  Sceneries
//
//  Created by Paolo Manna on 21/08/2020.
//  Copyright © 2020 MongoDB. All rights reserved.
//

import Foundation
import MapKit

struct FlickrPhoto {
	var imageId: String	= ""
	var secret: String	= ""
	var server: String	= ""
	var title: String?
	var owner: String?
	var location: CLLocation?
	
	init(with dict: [String: Any]) {
		// Convert from Flickr API to object
		imageId		= dict["id"] as! String
		secret		= dict["secret"] as! String
		server		= dict["server"] as! String
		title		= dict["title"] as? String
		owner		= dict["ownername"] as? String
		
		if let lat = Double(dict["latitude"] as? String ?? ""), let lon = Double(dict["longitude"] as? String ?? "") {
			location	= CLLocation(latitude: lat, longitude: lon)
		}
	}
}

class FlickrAnnotation: MKPointAnnotation {
	override var title: String?	{
		get { photo.title }
		set { photo.title	= newValue }
	}

	override var subtitle: String?	{
		get { photo.owner }
		set { photo.owner	= newValue }
	}

	override var coordinate: CLLocationCoordinate2D	{
		get { photo.location!.coordinate }
		set { photo.location = CLLocation(latitude: newValue.latitude, longitude: newValue.longitude) }
	}
	
	var photo: FlickrPhoto!

	convenience init(photo: FlickrPhoto) {
		self.init()
		
		self.photo	= photo
	}
	
	func thumbnailURL() -> URL {
		let thumbnailStr	= "https://live.staticflickr.com/\(photo.server)/\(photo.imageId)_\(photo.secret)_m.jpg"
		
		return URL(string: thumbnailStr)!
	}
	
	func annotationView() -> MKMarkerAnnotationView? {
		// NOTE: This needs to be called on the main thread, due to the use of UI structures
		let annotationView	= MKMarkerAnnotationView(annotation: self, reuseIdentifier: "flickrAnnotation")
		
		annotationView.glyphImage		= UIImage(named: "FlickrMarker")
		annotationView.markerTintColor	= .systemPurple
		annotationView.glyphTintColor	= .systemTeal
		
		annotationView.rightCalloutAccessoryView	= UIButton(type: .contactAdd)
		
		annotationView.canShowCallout	= true
		
		// TODO: A more complex callout view?
		let calloutView = UIImageView()
		
		// setup constraints for custom view
		calloutView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			calloutView.widthAnchor.constraint(equalToConstant: 160.0),
			calloutView.heightAnchor.constraint(equalToConstant: 75.0)
		])

		calloutView.downloadedFrom(url: thumbnailURL())
		
		annotationView.detailCalloutAccessoryView	= calloutView
		
		return annotationView
	}
}

class FlickrAPIService {
	var service	= APIService()
	var apiKey	= ""
	
	convenience init(apiKey: String) {
		self.init()
		
		service.serviceString	= "www.flickr.com"
		service.basePath		= "/services/rest"
		self.apiKey				= apiKey
	}
	
	func picturesAround(latitude: Double, longitude: Double, radius: Double, completion: @escaping (Error?, [FlickrPhoto]?) -> Void) {
		let params	= [
			"method": "flickr.photos.search",
			"api_key": apiKey,
			"lat": String(latitude),
			"lon": String(longitude),
			"radius": String(radius),
			"extras": "owner_nam,geo",
			"format": "json",
			"nojsoncallback": "1",
			"per_page": "100"
		]
		
		service.post(endpoint: "", query: params) { error, response in
			if error == nil, let respDict = response as? [String: Any] {
				guard let dictArray = (respDict["photos"] as? [String: Any])?["photo"] as? [[String: Any]] else {
					completion(NSError(domain: Bundle.main.bundleIdentifier!,
					                   code: -1,
					                   userInfo: [NSLocalizedDescriptionKey: "Unrecognized response format"]), nil)
					return
				}
				
				let photoArray	= dictArray.map { FlickrPhoto(with: $0) }
				
				completion(error, photoArray)
			} else {
				completion(error, nil)
			}
		}
	}
}
