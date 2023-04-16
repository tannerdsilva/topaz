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
	class ProfilesEngine:ObservableObject, ExperienceEngine {
		static let name = "profile-engine.mdb"
		static let deltaSize = size_t(1e10)
		static let maxDBs:MDB_dbi = 2
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let base:URL
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

		required init(base:URL, env:QuickLMDB.Environment, publicKey:nostr.Key) throws {
			self.base = base
			self.env = env
			self.pubkey = publicKey
			self.logger = Topaz.makeDefaultLogger(label:"profile-engine.mdb")
			let newTrans = try Transaction(env, readOnly:false)
			self.profilesDB = try env.openDatabase(named:Databases.profiles.rawValue, flags:[.create], tx:newTrans)
			self.profile_asofDB = try env.openDatabase(named:Databases.profile_asof.rawValue, flags:[.create], tx:newTrans)
			try self.profilesDB.setCompare(tx:newTrans, nostr.Key.mdbCompareFunction)
			do {
				let myProfile = try self.profilesDB.getEntry(type:Data.self, forKey:pubkey, tx:newTrans)!
				let decoded = try decoder.decode(nostr.Profile.self, from:myProfile)
				_currentUserProfile = Published(initialValue:decoded)
			} catch LMDBError.notFound {
				_currentUserProfile = Published(initialValue:nostr.Profile())
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
		func setPublicKeys(_ profiles:[nostr.Key:nostr.Profile], tx someTrans:QuickLMDB.Transaction) throws {
			let newTrans = try QuickLMDB.Transaction(self.env, readOnly:false, parent:someTrans)
			let encoder = JSONEncoder()
			let profileCursor = try self.profilesDB.cursor(tx:newTrans)
			for (pubkey, curProfile) in profiles {
				let encoded = try encoder.encode(curProfile)
				try profileCursor.setEntry(value:encoded, forKey:pubkey)
			}
			if let hasMyProfile = profiles[pubkey] {
				Task.detached { @MainActor [weak self, myprof = hasMyProfile] in
					guard let self = self else { return }
					self.currentUserProfile = myprof
				}
			}
			try newTrans.commit()
		}
	}
}
	
