//
//  Project.swift
//  Task Tracker
//
//  Created by MongoDB on 2020-05-07.
//  Copyright © 2020 MongoDB, Inc. All rights reserved.
//

import CoreLocation
import Foundation
import RealmSwift

typealias UserId = ObjectId

enum PhotoStatus: String {
	case ToSee
	case Unworthy
	case CantMiss
}

class Location: EmbeddedObject {
	@objc dynamic var latitude: CLLocationDegrees	= 0.0
	@objc dynamic var longitude: CLLocationDegrees	= 0.0
	
	var clLocation: CLLocation {
		return CLLocation(latitude: latitude, longitude: longitude)
	}
	
	convenience init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
		self.init()
		
		self.latitude	= latitude
		self.longitude	= longitude
	}
	
	convenience init(clLocation: CLLocation) {
		self.init()
		
		latitude	= clLocation.coordinate.latitude
		longitude	= clLocation.coordinate.longitude
	}
}

class PhotoView: EmbeddedObject {
	@objc dynamic var imageId: String	= ""
	@objc dynamic var secret: String	= ""
	@objc dynamic var server: String	= ""
	@objc dynamic var title: String?
	@objc dynamic var owner: String?
	@objc dynamic var status = PhotoStatus.ToSee.rawValue
	
	@objc dynamic var location: Location?
	
	var statusEnum: PhotoStatus {
		get { return PhotoStatus(rawValue: status) ?? .ToSee }
		set { status = newValue.rawValue }
	}

	convenience init(with photo: FlickrPhoto) {
		self.init()
		
		// Convert from Flickr API to object
		imageId		= photo.imageId
		secret		= photo.secret
		server		= photo.server
		title		= photo.title
		owner		= photo.owner
		
		if let loc = photo.location {
			location	= Location(clLocation: loc)
		}
	}
	
	func thumbnailURL() -> URL {
		let thumbnailStr	= "https://live.staticflickr.com/\(server)/\(imageId)_\(secret)_s.jpg"
		
		return URL(string: thumbnailStr)!
	}
	
	func imageURL() -> URL {
		let imageStr	= "https://live.staticflickr.com/\(server)/\(imageId)_\(secret)_b.jpg"
		
		return URL(string: imageStr)!
	}
}

class ViewPoint: EmbeddedObject {
	@objc dynamic var name: String	= ""
	@objc dynamic var location: Location?
	
	let photos	= List<PhotoView>()
	
	convenience init(name: String, location: CLLocation?) {
		self.init()
		
		self.name		= name
		if location != nil {
			self.location	= Location(clLocation: location!)
		}
	}
}

class Journey: Object {
	@objc dynamic var _id = ObjectId.generate()
	@objc dynamic var _partition: UserId?
	@objc dynamic var name: String	= ""
	
	let viewPoints	= List<ViewPoint>()
	
	override static func primaryKey() -> String? { "_id" }
    
	convenience init(partition: UserId, name: String) {
		self.init()
		
		_partition = partition
		self.name = name
	}
}
