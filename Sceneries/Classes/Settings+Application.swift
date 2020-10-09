//
//  Settings+Application.swift
//  Sceneries
//
//  Created by Paolo Manna on 24/08/2020.
//  Copyright © 2020 MongoDB. All rights reserved.
//

import Foundation

extension Settings {
	var userName: String? {
		get { return value(forKey: "UserName") as? String }
		set { setValue(newValue, forKey: "UserName") }
	}
	
	var locationEnabled: Bool {
		get { return value(forKey: "LocationEnabled") as? Bool ?? false }
		set { setValue(newValue, forKey: "LocationEnabled") }
	}
}
