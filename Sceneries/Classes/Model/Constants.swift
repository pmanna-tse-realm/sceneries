//
//  Constants.swift
//  TaskTracker2
//
//  Created by Paolo Manna on 14/08/2020.
//  Copyright © 2020 MongoDB. All rights reserved.
//

import Foundation
import RealmSwift

struct Constants {
	// Set this to your Realm App ID found in the Realm UI.
	static let REALM_APP_ID = "sceneries-iivuy"
	// Set this to your Flickr API Key.
	static let FLICKR_API_KEY = "f42cf134f5abb7296ba3af1bf0cba349"
}

let app				= App(id: Constants.REALM_APP_ID)
let flickrService	= FlickrAPIService(apiKey: Constants.FLICKR_API_KEY)
