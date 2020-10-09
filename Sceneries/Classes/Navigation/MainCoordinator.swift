//
//  MainCoordinator.swift
//  TaskTracker2
//
//  Created by Paolo Manna on 14/08/2020.
//  Copyright © 2020 MongoDB. All rights reserved.
//

import RealmSwift
import UIKit

class MainCoordinator: NSObject, Coordinator {
	var childCoordinators = [Coordinator]()
	var navigationController: NavigationControllerWithError

	init(navigationController: NavigationControllerWithError) {
		self.navigationController = navigationController
	}

	func start() {
		app.syncManager.logLevel	= .info
		
		let vc = JourneyListViewController.instantiate()
        
		vc.coordinator	= self
		
		navigationController.pushViewController(vc, animated: false)
	}
	
	func showMap(for journey: Journey, in realm: Realm) {
		let vc = JourneyMapViewController.instantiate()
        
		vc.coordinator	= self
		vc.journey		= journey
		vc.realm		= realm
		
		navigationController.pushViewController(vc, animated: true)
	}
}
