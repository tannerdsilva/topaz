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
	let dispatcher:Dispatcher<Topaz.Notification>
	
	typealias NotificationType = Topaz.Notification
	
	static let name = "topaz-base.mdb"
	static let deltaSize = SizeMode.fixed(size_t(100000000))
	static let maxDBs:MDB_dbi = 1
	static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir]
	let env:QuickLMDB.Environment
	let pubkey:nostr.Key
	let base:URL

	// various states the app can be in
	enum State:UInt8, MDB_convertible {
		case welcomeFlow = 0
		case operating = 1
	}
	
	private enum Databases:String {
		case app_metadata = "app_metadata"
	}

	private enum Metadatas:String {
		case appState = "appState"					// State
		case currentUser = "currentUser"			// nostr.Key
		case tosAcknowledged = "tosAcknlowledged?"	// Foundation.Date
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
	@Published public var isTOSAcknowledged:Foundation.Date? {
		willSet {
			if newValue == nil {
				try? self.app_metadata.deleteEntry(key:Metadatas.tosAcknowledged.rawValue, tx:nil)
				return
			} else {
				do {
					try self.app_metadata.setEntry(value:newValue!, forKey:Metadatas.tosAcknowledged.rawValue, tx:nil)
					self.logger.info("committed transaction to update TOS acknowledgement.", metadata:["acknowledged": "\(String(describing: isTOSAcknowledged))"])
				} catch let error {
					self.logger.critical("could not commit database transaction.", metadata:["error": "\(error)"])
				}
			}
		}
	}
	
	/// the primary store for the application users and their private keys
	var userStore:UserStore
	
	@Published public private(set) var currentUX:DBUX?

	required init(base: URL, env docEnv: QuickLMDB.Environment, keyPair:nostr.KeyPair, dispatcher:Dispatcher<NotificationType>) throws {
		self.dispatcher = dispatcher
		self.pubkey = keyPair.pubkey
		self.env = docEnv
		self.base = base
		let subTrans = try Transaction(docEnv, readOnly:false)
		self.userStore = try Topaz.launchExperienceEngine(UserStore.self, from:self.base.deletingLastPathComponent(), for:nostr.KeyPair(pubkey: nostr.Key.nullKey(), privkey: nostr.Key.nullKey()), dispatcher:dispatcher)
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
			_isTOSAcknowledged = Published(wrappedValue:try getMetadata.getEntry(type:Foundation.Date.self, forKey:Metadatas.tosAcknowledged.rawValue, tx:subTrans)!)
		} catch LMDBError.notFound {
			_isTOSAcknowledged = Published(wrappedValue:nil)
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
			currentUX = nil
		} else {
			let getKeypair = try self.userStore.keypair(pubkey:curUser!)
			currentUX = try! DBUX(app:self, base:base.deletingLastPathComponent(), keypair:getKeypair, appDispatcher: dispatcher)
		}
		try subTrans.commit()
		
		Task.detached { [dsp = dispatcher, userstore = self.userStore] in
			await dsp.addListener(forEventType:Topaz.Notification.userProfileInfoUpdated) { [ust = userstore] _, newProf in
				guard let getAccount = newProf as? Topaz.Account else {
					return
				}
				Task.detached { @MainActor in
					try? ust.updateUserProfile(getAccount.profile, for:getAccount.key)
				}
			}
		}
	}

	//set a user to be the currently assigned user
	@MainActor func setCurrentlyLoggedInUser(_ publicKey:nostr.Key, tx someTrans:QuickLMDB.Transaction? = nil) throws {
		let newTrans = try QuickLMDB.Transaction(self.env, readOnly:false, parent:someTrans)
		// verify that the public key exists
		let getKeypair = try self.userStore.keypair(pubkey:publicKey)
		let asUX = try DBUX(app:self, base:Topaz.findApplicationBase(), keypair:getKeypair, appDispatcher: dispatcher)
		currentUX = asUX
		try self.app_metadata.setEntry(value:publicKey, forKey:Metadatas.currentUser.rawValue, tx:newTrans)
		try newTrans.commit()
	}
	
	@MainActor func logOutOfCurrentUser(tx someTrans:QuickLMDB.Transaction? = nil) throws {
		let newTrans = try QuickLMDB.Transaction(self.env, readOnly:false, parent:someTrans)
		try self.app_metadata.deleteEntry(key:Metadatas.currentUser.rawValue, tx:newTrans)
		currentUX = nil
		try newTrans.commit()
	}
	
	/// installs a user in the application and ensures that the state of the app is updated
	@MainActor func installUser(publicKey:nostr.Key, privateKey:nostr.Key, profile:nostr.Profile = nostr.Profile()) throws {
		let newTrans = try QuickLMDB.Transaction(self.env, readOnly:false)
		try self.app_metadata.setEntry(value:ApplicationModel.State.operating, forKey:Metadatas.appState.rawValue, tx:newTrans)
		self.objectWillChange.send()
		_state = Published(wrappedValue:.operating)
		try! self.userStore.addUser(publicKey, privateKey:privateKey, profile:profile)
		try! setCurrentlyLoggedInUser(publicKey, tx:newTrans)
		try! newTrans.commit()
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
				currentUX = nil
				_state = Published(wrappedValue:.welcomeFlow)
			}
		}
	}
}

extension ApplicationModel {
	class UserStore:ObservableObject, ExperienceEngine {
		
		let dispatcher:Dispatcher<NotificationType>
		
		typealias NotificationType = Topaz.Notification
		
		static let name = "topaz-users.mdb"
		static let deltaSize = SizeMode.fixed(size_t(250000000))
		static let maxDBs:MDB_dbi = 2
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let pubkey:nostr.Key
		let base:URL

		fileprivate enum Databases:String {
			case app_users = "app_users"
			case profiledb = "profiledb"
		}
		let decoder = JSONDecoder()
		let encoder = JSONEncoder()
		
		let env:QuickLMDB.Environment		// the environment this store is in
		let userDB:Database 				// [nostr.Key:nostr.Key] where (pubkey : privkey)
		let profileDB:Database

		/// all the users in the store
		@Published public private(set) var users:[Topaz.Account]

		required init(base: URL, env docEnv: QuickLMDB.Environment, keyPair:nostr.KeyPair, dispatcher:Dispatcher<NotificationType>) throws {
			self.dispatcher = dispatcher
			self.env = docEnv
			self.base = base
			let subTrans = try QuickLMDB.Transaction(docEnv, readOnly:false)
			self.userDB = try docEnv.openDatabase(named:Databases.app_users.rawValue, flags:[.create], tx:subTrans)
			self.profileDB = try docEnv.openDatabase(named:Databases.profiledb.rawValue, flags:[.create], tx:subTrans)
			let profileCursor = try profileDB.cursor(tx:subTrans)
			var users = [Topaz.Account]()
			let decoder = JSONDecoder()
			for (pubKey, profileInfo) in profileCursor {
				let nkey = nostr.Key(pubKey)!
				let getData = Data(profileInfo)!
				let parsed = try decoder.decode(nostr.Profile.self, from:getData)
				users.append(Topaz.Account(key:nkey, profile: parsed))
			}
			_users = Published(wrappedValue:users)
			self.pubkey = keyPair.pubkey
			try subTrans.commit()
			
		}
		
		fileprivate func reloadAllUserInfo(profileCursor cursor:QuickLMDB.Cursor) throws -> [Topaz.Account] {
			var allAccounts = [Topaz.Account]()
			for (curPK, curProfile) in cursor {
				let decoded = try decoder.decode(nostr.Profile.self, from:Data(curProfile)!)
				let makeAccount = Topaz.Account(key:nostr.Key(curPK)!, profile:decoded)
				allAccounts.append(makeAccount)
			}
			return allAccounts
		}

		/// add a user to the store
		@MainActor fileprivate func addUser(_ publicKey:nostr.Key, privateKey:nostr.Key, profile:nostr.Profile) throws {
			let subTrans = try QuickLMDB.Transaction(env, readOnly:false)
			self.objectWillChange.send()
			users.append(Topaz.Account(key:publicKey, profile:profile))
			try userDB.setEntry(value:privateKey, forKey:publicKey, tx:subTrans)
			let encodedObject = try encoder.encode(profile)
			let profilesCursor = try self.profileDB.cursor(tx:subTrans)
			try profilesCursor.setEntry(value:encodedObject, forKey:publicKey)
			self.users = try self.reloadAllUserInfo(profileCursor: profilesCursor)
			try subTrans.commit()
		}

		@MainActor func updateUserProfile(_ profileInfo:nostr.Profile, for key:nostr.Key) throws {
			let subTrans = try QuickLMDB.Transaction(env, readOnly:false)
			self.objectWillChange.send()
			let getCursor = try self.profileDB.cursor(tx:subTrans)
			let encodedObject = try encoder.encode(profileInfo)
			try getCursor.setEntry(value:encodedObject, forKey:key)
			self.users = try self.reloadAllUserInfo(profileCursor: getCursor)
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
		func allUsers() throws -> [nostr.Key:nostr.Profile] {
			let someTrans = try QuickLMDB.Transaction(env, readOnly:true)
			let userCursor = try userDB.cursor(tx:someTrans)
			var buildPubs = [nostr.Key:nostr.Profile]()
			for (curPub, curProfile) in userCursor {
				buildPubs[nostr.Key(curPub)!] = try decoder.decode(nostr.Profile.self, from:Data(curProfile)!)
			}
			try someTrans.commit()
			return buildPubs
		}
		
		/// remove a user from the store
		func removeUser(pubkey:nostr.Key) throws {
			let subTrans = try Transaction(env, readOnly:false)
			try self.userDB.deleteEntry(key:pubkey, tx:subTrans)
			users.removeAll(where:{ $0.key == pubkey })
			try subTrans.commit()
		}
	}
}
