//
//  ApplicationModel.swift
//  topaz
//
//  Created by Tanner Silva on 3/4/23.
//

//import Foundation
import SwiftUI
import QuickLMDB
import struct CLMDB.MDB_dbi
import SwiftBlake2
import Logging
import AsyncAlgorithms

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

// not based because users get directories created alongside the same `base` as this engine
class ApplicationModel:ObservableObject, ExperienceEngine {
	static let name = "topaz-base.mdb"
	static let deltaSize = size_t(250000000)
	static let maxDBs:MDB_dbi = 1
	static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
	let env:QuickLMDB.Environment
	let pubkey:nostr.Key
	let base:URL

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
		case currentUser = "currentUser"			// nostr.Key
		case tosAcknowledged = "tosAcknlowledged?"	// Bool
	}

	
	let logger = Topaz.makeDefaultLogger(label:"topaz-base.mdb")
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
	var userStore:UserStore
	
	@Published public private(set) var currentUX:DBUX?

	required init(base: URL, env docEnv: QuickLMDB.Environment, publicKey: nostr.Key) throws {
		self.pubkey = publicKey
		self.env = docEnv
		self.base = base
		let subTrans = try Transaction(docEnv, readOnly:false)
		self.userStore = try Topaz.launchExperienceEngine(UserStore.self, from:self.base.deletingLastPathComponent(), for:nostr.Key.nullKey())
		let getMetadata = try docEnv.openDatabase(named:Databases.app_metadata.rawValue, flags:[.create], tx:subTrans)
		self.app_metadata = getMetadata
		// load the app state
		do {
			_state = Published(wrappedValue:try getMetadata.getEntry(type:State.self, forKey:Metadatas.appState.rawValue, tx:subTrans)!)
		} catch LMDBError.notFound {
			_state = Published(wrappedValue:.welcomeFlow)
		}
		// load the TOS acknowledgement
		do {
			_isTOSAcknowledged = Published(wrappedValue:try getMetadata.getEntry(type:Bool.self, forKey:Metadatas.tosAcknowledged.rawValue, tx:subTrans)!)
		} catch LMDBError.notFound {
			_isTOSAcknowledged = Published(wrappedValue:false)
		}
		// determine the current user logged in
		let curUser:nostr.Key?
		do {
			curUser = try getMetadata.getEntry(type:nostr.Key.self, forKey:Metadatas.currentUser.rawValue, tx:subTrans)!
		} catch LMDBError.notFound {
			curUser = nil
		}
		// initialize the current user experience if there is one
		if curUser == nil {
			_currentUX = Published(wrappedValue:nil)
		} else {
			let getKeypair = try self.userStore.keypair(pubkey:curUser!)
			let loadUX = try DBUX(base:base, keypair:getKeypair)
			_currentUX = Published(wrappedValue:loadUX)
		}
		try subTrans.commit()
	}

	//set a user to be the currently assigned user
	@MainActor func setCurrentlyLoggedInUser(_ publicKey:nostr.Key, tx someTrans:QuickLMDB.Transaction? = nil) throws {
		let newTrans = try QuickLMDB.Transaction(self.env, readOnly:false, parent:someTrans)
		// verify that the public key exists
		let getKeypair = try self.userStore.keypair(pubkey:publicKey)
		self.objectWillChange.send()
		let asUX = try DBUX(base:Topaz.findApplicationBase(), keypair:getKeypair)
		_currentUX = Published(wrappedValue:asUX)
		try self.app_metadata.setEntry(value:publicKey, forKey:Metadatas.currentUser.rawValue, tx:newTrans)
		try newTrans.commit()
	}
	
	/// installs a user in the application and ensures that the state of the app is updated
	@MainActor func installUser(publicKey:nostr.Key, privateKey:nostr.Key) throws {
		let newTrans = try QuickLMDB.Transaction(self.env, readOnly:false)
		self.objectWillChange.send()
		_state = Published(wrappedValue:.onboarded)
		try self.app_metadata.setEntry(value:ApplicationModel.State.onboarded, forKey:Metadatas.appState.rawValue, tx:newTrans)
		try self.userStore.addUser(publicKey, privateKey:privateKey)
		try setCurrentlyLoggedInUser(publicKey, tx:newTrans)
		try newTrans.commit()
		_currentUX = Published(wrappedValue:try! DBUX(base:Topaz.findApplicationBase(), keypair:nostr.KeyPair(pubkey:publicKey, privkey:privateKey)))
	}


	/// removes a user from the application and ensures that the state of the app is updated if there are no more users
	@MainActor func removeUser(publicKey:nostr.Key, tx someTrans:QuickLMDB.Transaction? = nil) throws {
		let newTrans = try QuickLMDB.Transaction(self.env, readOnly:false, parent:someTrans)
		self.objectWillChange.send()
		try self.userStore.removeUser(pubkey:publicKey)
		// if this is the current user
		if self.currentUX!.keypair.pubkey == publicKey {
			let getUsers = try self.userStore.allUsers()
			if getUsers.count == 0 {
				self.objectWillChange.send()
				_currentUX = Published(wrappedValue:nil)
				_state = Published(wrappedValue:.welcomeFlow)
			}
		}
	}
}

extension ApplicationModel {
	class UserStore:ObservableObject, ExperienceEngine {
		static let name = "topaz-users.mdb"
		static let deltaSize = size_t(250000000)
		static let maxDBs:MDB_dbi = 1
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let pubkey:nostr.Key
		let base:URL

		fileprivate enum Databases:String {
			case app_users = "app_users"
		}
		
		let env:QuickLMDB.Environment		// the environment this store is in
		let userDB:Database 				// [nostr.Key:nostr.Key] where (pubkey : privkey)

		/// all the users in the store
		@Published public private(set) var users:Set<nostr.Key>

		required init(base: URL, env docEnv: QuickLMDB.Environment, publicKey: nostr.Key) throws {
			self.env = docEnv
			self.base = base
			let subTrans = try QuickLMDB.Transaction(docEnv, readOnly:false)
			self.userDB = try docEnv.openDatabase(named:Databases.app_users.rawValue, flags:[.create], tx:subTrans)
			let userCursor = try userDB.cursor(tx:subTrans)
			var users = Set<nostr.Key>()
			for (pubKey, _) in userCursor {
				users.update(with:nostr.Key(pubKey)!)
			}
			_users = Published(wrappedValue:users)
			self.pubkey = publicKey
			try subTrans.commit()
		}

		/// add a user to the store
		@MainActor fileprivate func addUser(_ publicKey:nostr.Key, privateKey:nostr.Key) throws {
			let subTrans = try QuickLMDB.Transaction(env, readOnly:false)
			self.objectWillChange.send()
			try userDB.setEntry(value:privateKey, forKey:publicKey, flags:[.noOverwrite], tx:subTrans)
			try subTrans.commit()
		}

		/// get a user's private key
		func getUserPrivateKey(pubKey:nostr.Key) throws -> nostr.Key? {
			return try userDB.getEntry(type:nostr.Key.self, forKey:pubKey, tx:nil)!
		}
		
		func keypair(pubkey:nostr.Key) throws -> nostr.KeyPair {
			let someTrans = try QuickLMDB.Transaction(env, readOnly:true)
			let privKey = try self.userDB.getEntry(type:nostr.Key.self, forKey:pubkey, tx:someTrans)!
			return nostr.KeyPair(pubkey:pubkey, privkey:privKey)
		}

		/// get all the users in the store
		/// - if there are no users, a set of zero items are returned
		func allUsers() throws -> Set<nostr.Key> {
			let someTrans = try QuickLMDB.Transaction(env, readOnly:true)
			let userCursor = try userDB.cursor(tx:someTrans)
			var buildPubs = Set<nostr.Key>()
			for (curPub, _) in userCursor {
				buildPubs.update(with:nostr.Key(curPub)!)
			}
			try someTrans.commit()
			return buildPubs
		}
		
		/// remove a user from the store
		func removeUser(pubkey:nostr.Key) throws {
			let subTrans = try Transaction(env, readOnly:false)
			try self.userDB.deleteEntry(key:pubkey, tx:subTrans)
			try subTrans.commit()
		}
	}
}
