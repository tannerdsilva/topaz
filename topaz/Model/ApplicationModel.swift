//
//  ApplicationModel.swift
//  topaz
//
//  Created by Tanner Silva on 3/4/23.
//

//import Foundation
import SwiftUI
import QuickLMDB

extension RawRepresentable where Self:MDB_convertible, RawValue:MDB_convertible {
	public init?(_ value:MDB_val) {
		guard let hasRV = RawValue(value), let makeSelf = Self(rawValue:hasRV) else {
			return nil
		}
		self = makeSelf
	}
	public func asMDB_val<R>(_ valFunc:(inout MDB_val) throws -> R) rethrows -> R {
		return try rawValue.asMDB_val(valFunc)
	}
}

class ApplicationModel:ObservableObject {
	// various states the app can be in
	enum State:UInt8, MDB_convertible {
		case welcomeFlow = 0
		case onboarded = 1
	}
	
	private enum Databases:String {
		case app_metadata = "app_metadata"
	}

	private enum Metadatas:String {
		case appState = "appState"					// State
		case currentUser = "currentUser"
		case tosAcknowledged = "tosAcknlowledged?"	// Bool
	}

	let logger = Topaz.makeDefaultLogger(label:"app-metadata")

	let env:QuickLMDB.Environment
	let app_metadata:Database			// general metadata
	
	/// the state of the app
	@Published public var state:State {
		didSet {
			do {
				try self.app_metadata.setEntry(value:state, forKey:Metadatas.appState.rawValue, tx:nil)
				self.logger.info("committed transaction to update state.", metadata:["state": "\(state)"])
			} catch let error {
				self.logger.critical("could not commit database transaction.", metadata:["error": "\(error)"])
			}
		}
	}

	/// whether the user has acknowledged the terms of service
	@Published public var isTOSAcknowledged:Bool {
		didSet {
			do {
				try self.app_metadata.setEntry(value:isTOSAcknowledged, forKey:Metadatas.tosAcknowledged.rawValue, tx:nil)
				self.logger.info("committed transaction to update TOS acknowledgement.", metadata:["acknowledged": "\(isTOSAcknowledged)"])
			} catch let error {
				self.logger.critical("could not commit database transaction.", metadata:["error": "\(error)"])
			}
		}
	}
	
	/// the primary store for the application users and their private keys
	@Published var userStore:UserStore
	
	@Published var defaultUE:UE?

	/// the primary store for the user sessions
	init(_ docEnv:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction? = nil) throws {
		self.env = docEnv
		
		// open the app metadata database
		let subTrans = try Transaction(docEnv, readOnly:false, parent:someTrans)
		self.app_metadata = try docEnv.openDatabase(named:Databases.app_metadata.rawValue, flags:[.create], tx:subTrans)
		
		// load the app state
		do {
			_state = Published(wrappedValue:try self.app_metadata.getEntry(type:State.self, forKey:Metadatas.appState.rawValue, tx:subTrans)!)
		} catch LMDBError.notFound {
			_state = Published(wrappedValue:.welcomeFlow)
		}
		// load the TOS acknowledgement
		do {
			_isTOSAcknowledged = Published(wrappedValue:try self.app_metadata.getEntry(type:Bool.self, forKey:Metadatas.tosAcknowledged.rawValue, tx:subTrans)!)
		} catch LMDBError.notFound {
			_isTOSAcknowledged = Published(wrappedValue:false)
		}
		self.userStore = try UserStore(docEnv, tx:subTrans)
		let getUsers = try self.userStore.allUsers(tx:subTrans)
		if getUsers.isEmpty {
			_defaultUE = Published(wrappedValue:nil)
		} else {
			let getKeypair = try self.userStore.keypair(pubkey:getUsers.randomElement()!, tx:subTrans)
			_defaultUE = Published(wrappedValue:try UE(keypair:getKeypair))
		}
		try subTrans.commit()
	}
	
	/// installs a user in the application and ensures that the state of the app is updated
	@MainActor func installUser(publicKey:String, privateKey:String, tx someTrans:QuickLMDB.Transaction? = nil) throws {
		let newTrans = try QuickLMDB.Transaction(self.env, readOnly:false, parent:someTrans)
		self.objectWillChange.send()
		_state = Published(wrappedValue:.onboarded)
		try self.userStore.addUser(publicKey, privateKey:privateKey, tx:newTrans)
		try self.app_metadata.setEntry(value:State.onboarded, forKey:Metadatas.appState.rawValue, tx:newTrans)
		try newTrans.commit()
		_defaultUE = Published(wrappedValue:try! UE(keypair:KeyPair(pubkey:publicKey, privkey:privateKey)))
	}


	/// removes a user from the application and ensures that the state of the app is updated if there are no more users
	func removeUser(publicKey:String, tx someTrans:QuickLMDB.Transaction? = nil) throws {
		let newTrans = try QuickLMDB.Transaction(self.env, readOnly:false, parent:nil)
		self.objectWillChange.send()
		try self.userStore.removeUser(publicKey, tx:newTrans)
		let allUsers = try self.userStore.allUsers(tx:newTrans)
		if (allUsers.count == 0) {
			_state = Published(wrappedValue:.welcomeFlow)
			try self.app_metadata.setEntry(value:State.welcomeFlow, forKey:Metadatas.appState.rawValue, tx:newTrans)
		} else {
			
		}
	}
}

extension ApplicationModel {
	class UserStore:ObservableObject {
		fileprivate enum Databases:String {
			case app_users = "app_users"
		}
		
		let env:QuickLMDB.Environment		// the environment this store is in
		let userDB:Database 				// [String:String] where (pubkey : privkey)

		/// all the users in the store
		@Published public private(set) var users:Set<String>
		init(_ docEnv:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction? = nil) throws {
			self.env = docEnv
			let subTrans = try QuickLMDB.Transaction(docEnv, readOnly:false, parent:someTrans)
			self.userDB = try docEnv.openDatabase(named:Databases.app_users.rawValue, flags:[.create], tx:subTrans)
			let userCursor = try userDB.cursor(tx:subTrans)
			var users = Set<String>()
			for (pubKey, _) in userCursor {
				users.update(with:String(pubKey)!)
			}
			_users = Published(wrappedValue:users)
			try subTrans.commit()
		}
		
		/// add a user to the store
		@MainActor fileprivate func addUser(_ publicKey:String, privateKey:String, tx someTrans:QuickLMDB.Transaction? = nil) throws {
			let subTrans = try QuickLMDB.Transaction(env, readOnly:false, parent:someTrans)
			self.objectWillChange.send()
			try userDB.setEntry(value:privateKey, forKey:publicKey, tx:subTrans)
			try subTrans.commit()
		}

		/// get a user's private key
		func getUserPrivateKey(pubKey:String, tx someTrans:QuickLMDB.Transaction?) throws -> String? {
			return try userDB.getEntry(type:String.self, forKey:pubKey, tx:someTrans)!
		}
		
		func keypair(pubkey:String, tx someTrans:QuickLMDB.Transaction?) throws -> KeyPair {
			let privKey = try self.userDB.getEntry(type:String.self, forKey:pubkey, tx:someTrans)!
			return KeyPair(pubkey:pubkey, privkey:privKey)
		}

		/// get all the users in the store
		/// - if there are no users, a set of zero items are returned
		func allUsers(tx someTrans:QuickLMDB.Transaction) throws -> Set<String> {
			let userCursor = try userDB.cursor(tx:someTrans)
			var buildPubs = Set<String>()
			for (curPub, _) in userCursor {
				buildPubs.update(with:String(curPub)!)
			}
			return buildPubs
		}
		
		/// remove a user from the store
		func removeUser(_ publicKey:String, tx someTrans:QuickLMDB.Transaction? = nil) throws {
			let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
			try self.userDB.deleteEntry(key:publicKey, tx:subTrans)
			try subTrans.commit()
		}
	}
}
