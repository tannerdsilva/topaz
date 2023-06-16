//
//  ProfilesEngine.swift
//  topaz
//
//  Created by Tanner Silva on 4/14/23.
//

import Foundation
import QuickLMDB
import struct CLMDB.MDB_dbi
import SwiftBlake2
import Logging
import AsyncAlgorithms

extension DBUX {
	class ProfilesEngine:ObservableObject, SharedExperienceEngine {
		
		typealias NotificationType = DBUX.Notification
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let dispatcher: Dispatcher<DBUX.Notification>
		let env:QuickLMDB.Environment
		let pubkey:nostr.Key
		let logger:Logger

		enum Databases:String {
			case profiles = "profile-main"	// [nostr.Key:Profile]
			case profile_asof = "profile-asof"	// [nostr.Key:DBUX.Date]
		}

		let decoder = JSONDecoder()

		let profilesDB:Database
		let profile_asofDB:Database

		@MainActor @Published var currentUserProfile:nostr.Profile

		required init(env: QuickLMDB.Environment, keyPair:nostr.KeyPair, dispatcher: Dispatcher<DBUX.Notification>) throws {
			self.dispatcher = dispatcher
			self.env = env
			self.pubkey = keyPair.pubkey
			self.logger = Topaz.makeDefaultLogger(label:"profile-engine.mdb")
			let newTrans = try Transaction(env, readOnly:false)
			self.profilesDB = try env.openDatabase(named:Databases.profiles.rawValue, flags:[.create], tx:newTrans)
			self.profile_asofDB = try env.openDatabase(named:Databases.profile_asof.rawValue, flags:[.create], tx:newTrans)
			try self.profilesDB.setCompare(tx:newTrans, nostr.Key.mdbCompareFunction)
			do {
				let myProfile = try self.profilesDB.getEntry(type:Data.self, forKey:pubkey, tx:newTrans)!
				let getString = String(data:myProfile, encoding:.utf8)
				let decoded = try decoder.decode(nostr.Profile.self, from:myProfile)
				_currentUserProfile = Published(wrappedValue:decoded)
			} catch LMDBError.notFound {
				_currentUserProfile = Published(wrappedValue:nostr.Profile())
			}
			try newTrans.commit()
		}

		/// gets a profile from the database
		func getPublicKeys(publicKeys:Set<nostr.Key>, tx someTrans:QuickLMDB.Transaction) throws -> [nostr.Key:nostr.Profile] {
			let getCursor = try self.profilesDB.cursor(tx:someTrans)
			var profiles = [nostr.Key:nostr.Profile]()
			for curID in publicKeys {
				do {
					let getProfile = Data(try getCursor.getEntry(.set, key:curID).value)!
					let decoded = try self.decoder.decode(nostr.Profile.self, from:getProfile)
					profiles[curID] = decoded
				} catch LMDBError.notFound {
					continue
				}
			}
			return profiles
		}

		/// set a profile in the database
		func setPublicKeys(_ profiles:[nostr.Key:nostr.Profile], asOf:[nostr.Key:DBUX.Date], tx someTrans:QuickLMDB.Transaction) throws {
			let newTrans = try QuickLMDB.Transaction(self.env, readOnly:false, parent:someTrans)
			let encoder = JSONEncoder()
			var currentUserChanged:Bool = false
			let profileCursor = try self.profilesDB.cursor(tx:newTrans)
			let dateCursor = try self.profile_asofDB.cursor(tx:newTrans)
			for (pubkey, curProfile) in profiles {
				do {
					let getDate = DBUX.Date(try dateCursor.getEntry(.set, key:pubkey).value)!
					if getDate >= asOf[pubkey]! {
						continue
					}
				} catch LMDBError.notFound {}
				let encoded = try encoder.encode(curProfile)
				if pubkey == self.pubkey {
					currentUserChanged = true
				}
				try profileCursor.setEntry(value:encoded, forKey:pubkey)
				try dateCursor.setEntry(value:asOf[pubkey]!, forKey:pubkey)
			}
			try newTrans.commit()
			if currentUserChanged {
				Task.detached { @MainActor [weak self, myprof = profiles[pubkey]!] in
					guard let self = self else { return }
					self.currentUserProfile = myprof
					Task.detached(operation: { [disp = self.dispatcher, myprof = myprof] in
						await disp.fireEvent(DBUX.Notification.currentUserProfileUpdated, associatedObject:myprof)
					})
				}
			}
		}
	}
}
	
