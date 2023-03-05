//
//  ApplicationModel.swift
//  topaz
//
//  Created by Tanner Silva on 3/4/23.
//

import Foundation
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

struct ApplicationModel {
	/// the main engine for the app and its data
	class Metadata:ObservableObject {
		enum State:UInt8, MDB_convertible {
			case welcomeFlow = 0
			case onboarded = 1
		}
		
		fileprivate enum Databases:String {
			case app_metadata = "app_metadata"
		}

		fileprivate enum Metadatas:String {
			case appState = "appState"			// State
			case currentUser = "currentUser"
		}

		let logger = Topaz.makeDefaultLogger(label:"app-metadata")

		let env:QuickLMDB.Environment
		let app_metadata:Database
		
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
		
		/// the public key of the current user of the app
		@Published public var currentUserPublicKey:String? {
			didSet {
				print("is about to set")
				do {
					if let hasCurrentUser = currentUserPublicKey {
						try self.app_metadata.setEntry(value:hasCurrentUser, forKey:Metadatas.currentUser.rawValue, tx:nil)
						self.logger.info("committed transaction to update current user.", metadata:["user": "\(hasCurrentUser)"])
					} else {
						do {
							try self.app_metadata.deleteEntry(key:Metadatas.currentUser.rawValue, tx:nil)
							self.logger.info("committed transaction to remove current user.", metadata:["user": "\(currentUserPublicKey ?? "nil")"])
						} catch LMDBError.notFound {}
					}
				} catch let error {
					self.logger.critical("could not commit database transaction.", metadata:["error": "\(error)"])
				}
			}
		}

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
			// load the current user
			do {
				_currentUserPublicKey = Published(wrappedValue:try self.app_metadata.getEntry(type:String.self, forKey:Metadatas.currentUser.rawValue, tx:subTrans)!)
			} catch LMDBError.notFound {
				_currentUserPublicKey = Published(wrappedValue:nil)
			}
			try subTrans.commit()
		}
	}

	class UserStore:ObservableObject {
		fileprivate enum Databases:String {
			case app_users = "app_users"
		}
		
		struct User:Codable, Hashable, Equatable {
			let pubKey:String
			let privKey:String
		}
		
		let env:QuickLMDB.Environment
		let userDB:Database 	// [String:User] where (pubkey : User)

		init(_ docEnv:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction? = nil) throws {
			let subTrans = try QuickLMDB.Transaction(docEnv, readOnly:false, parent:someTrans)
			self.userDB = try docEnv.openDatabase(named:Databases.app_users.rawValue, flags:[.create], tx:subTrans)
			try subTrans.commit()
			self.env = docEnv
		}
		
		func addUser(_ user:User, tx someTrans:QuickLMDB.Transaction? = nil) throws {
			let subTrans = try QuickLMDB.Transaction(env, readOnly:false, parent:someTrans)
			self.objectWillChange.send()
			let asData = try JSONEncoder().encode(user)
			try userDB.setEntry(value:asData, forKey:user.pubKey, flags:[.noOverwrite], tx:subTrans)
			try subTrans.commit()
		}
		

		func allUsers(tx someTrans:QuickLMDB.Transaction? = nil) throws -> [User] {
			let newTrans = try Transaction(env, readOnly:true, parent:someTrans)
			let cursor = try userDB.cursor(tx:newTrans)
			var users = [User]()
			for (_, value) in cursor {
				let asData = Data(value)!
				let user = try JSONDecoder().decode(User.self, from:asData)
				users.append(user)
			}
			return users
		}
		
		func removeUser(_ user:User, tx someTrans:QuickLMDB.Transaction? = nil) throws {
			let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
			try self.userDB.deleteEntry(key:user.pubKey, tx:subTrans)
			try subTrans.commit()
		}
	}
}
