//
//  JourneyListViewController.swift
//  Sceneries
//
//  Created by Paolo Manna on 20/08/2020.
//  Copyright © 2020 MongoDB. All rights reserved.
//

import Realm
import RealmSwift
import UIKit

class JourneyListViewController: UITableViewController, Storyboarded {
	weak var coordinator: MainCoordinator?
    
	var realm: Realm!
	var journeys: Results<Journey>!
	var notificationToken: NotificationToken?
	var partitionValue: ObjectId!
	
	@IBOutlet var addButton: UIBarButtonItem!

	override func viewDidLoad() {
		super.viewDidLoad()
		
		addButton							= UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addButtonDidClick))
		addButton.isEnabled					= false
		navigationItem.rightBarButtonItem	= addButton
		
		tableView.tableFooterView			= UIView(frame: .zero)
		navigationItem.backBarButtonItem	= UIBarButtonItem(title: "Back", style: .plain, target: nil, action: nil)
		
		app.login(credentials: .anonymous) { maybeUser, error in
			DispatchQueue.main.async { [weak self] in
				let nav	= self?.navigationController as? NavigationControllerWithError
				
				guard error == nil else {
					nav?.postErrorMessage(message: "Login failed: \(error!.localizedDescription)")
					return
				}
				
				guard maybeUser != nil else {
					nav?.postErrorMessage(message: "Invalid User")
					return
				}
				
				self?.loadFromDB()
			}
		}
	}

	// MARK: - Actions
    
	func loadFromDB() {
		let nav	= navigationController as? NavigationControllerWithError
		
		if realm == nil {
			guard let user = app.currentUser, let userIdentity = try? ObjectId(string: user.id) else {
				nav?.postErrorMessage(message: "Must be logged in to access this view", isError: true)
				
				return
			}
			
			partitionValue	= userIdentity
			
			// Open a realm with the partition key set to the user.
			// TODO: When support for user data is available, use the user data's list of
			// available projects.
			do {
				realm = try Realm(configuration: user.configuration(partitionValue: partitionValue))
			} catch {
				nav?.postErrorMessage(message: error.localizedDescription, isError: true)
				
				return
			}
		}
		
		addButton.isEnabled		= true
		
		// Access all objects in the realm, sorted by _id so that the ordering is defined.
		journeys = realm.objects(Journey.self).sorted(byKeyPath: "_id")

		guard journeys != nil else {
			nav?.postErrorMessage(message: "No journeys found", isError: true)
			
			return
		}
		
		// Observe the projects for changes.
		notificationToken = journeys.observe { [weak self] changes in
			guard let tableView = self?.tableView else { return }
			switch changes {
			case .initial:
				// Results are now populated and can be accessed without blocking the UI
				tableView.reloadData()
			case let .update(_, deletions, insertions, modifications):
				// Query results have changed, so apply them to the UITableView.
				tableView.beginUpdates()
				// It's important to be sure to always update a table in this order:
				// deletions, insertions, then updates. Otherwise, you could be unintentionally
				// updating at the wrong index!
				tableView.deleteRows(at: deletions.map { IndexPath(row: $0, section: 0) },
				                     with: .automatic)
				tableView.insertRows(at: insertions.map { IndexPath(row: $0, section: 0) },
				                     with: .automatic)
				tableView.reloadRows(at: modifications.map { IndexPath(row: $0, section: 0) },
				                     with: .automatic)
				tableView.endUpdates()
			case let .error(error):
				// An error occurred while opening the Realm file on the background worker thread
				nav?.postErrorMessage(message: error.localizedDescription, isError: true)
			}
		}
	}
	
	@IBAction func addButtonDidClick() {
		guard realm != nil else { return }
		 
		// User clicked the add button.
		 
		let alertController = UIAlertController(title: "Add Journey", message: "", preferredStyle: .alert)

		alertController.addAction(UIAlertAction(title: "Save", style: .default, handler: { [weak self] _ -> Void in
			guard let self = self else { return }
			
			let textField = alertController.textFields![0] as UITextField
			let journey = Journey(partition: self.partitionValue, name: textField.text ?? "New Journey")
				 
			// All writes must happen in a write block.
			try! self.realm.write {
				self.realm.add(journey)
			}
		}))
		alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		alertController.addTextField(configurationHandler: { (textField: UITextField!) -> Void in
			textField.placeholder = "New Journey Name"
		})
		present(alertController, animated: true, completion: nil)
	}
	
	// MARK: - Table View

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return journeys?.count ?? 1
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		var cell: UITableViewCell!
		
		if let journeys = journeys, !journeys.isEmpty {
			let journey	= journeys[indexPath.row]
		
			cell	= tableView.dequeueReusableCell(withIdentifier: "journeyCell", for: indexPath)
		
			cell.textLabel!.text = journey.name
		} else {
			cell	= tableView.dequeueReusableCell(withIdentifier: "noDataCell", for: indexPath)
		}
		return cell
	}

	override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		// Return false if you do not want the specified item to be editable.
		if let journeys = journeys, !journeys.isEmpty {
			return true
		}
		return false
	}

	override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
		guard editingStyle == .delete else { return }
		
		// The user can swipe to delete Projects.
		let journey = journeys[indexPath.row]
		
		// All modifications must happen in a write block.
		try! realm.write {
			// Delete the project.
			realm.delete(journey)
		}
	}
	
	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		
		if let journeys = journeys, !journeys.isEmpty {
			let journey		= journeys[indexPath.row]
			
			coordinator?.showMap(for: journey, in: realm)
		}
	}
}
