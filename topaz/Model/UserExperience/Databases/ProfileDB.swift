//
//  ProfileDB.swift
//  topaz
//
//  Created by Tanner Silva on 3/17/23.
//

import Foundation
import QuickLMDB

// FRIENDS:
// a user may be considered a friend to the current user if the current user is following them
extension UE {
	class Profiles:ObservableObject {
		enum Databases:String {
			case profile_main = "_profiles-core"
		}

		let env:QuickLMDB.Environment
		fileprivate let decoder = JSONDecoder()
		
		let profilesDB:Database  // [String:Pofile] where the key is the pubkey

		init(_ env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
			let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
			self.env = env
			self.profilesDB = try env.openDatabase(named:Databases.profile_main.rawValue, flags:[.create], tx:subTrans)
			try subTrans.commit()
		}

		/// gets a profile from the database
		func getPublicKeys(publicKeys:Set<String>) throws -> [String:nostr.Profile] {
			let newTrans = try QuickLMDB.Transaction(self.env, readOnly:true)
			let getCursor = try self.profilesDB.cursor(tx:newTrans)
			var profiles = [String:nostr.Profile]()
			for curID in publicKeys {
				let getProfile = Data(try getCursor.getEntry(.set, key:curID).value)!
				let decoded = try self.decoder.decode(nostr.Profile.self, from:getProfile)
				profiles[curID] = decoded
			}
			try newTrans.commit()
			return profiles
		}

		/// set a profile in the database
		func setPublicKeys(_ profiles:[String:nostr.Profile]) throws {
			let newTrans = try QuickLMDB.Transaction(self.env, readOnly:false)
			let encoder = JSONEncoder()
			let profileCursor = try self.profilesDB.cursor(tx:newTrans)
			for (pubkey, curProfile) in profiles {
				let encoded = try encoder.encode(curProfile)
				try profileCursor.setEntry(value:encoded, forKey:pubkey)
			}
			try newTrans.commit()
		}
	}
}
