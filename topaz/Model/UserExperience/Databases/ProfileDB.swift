//
//  ProfileDB.swift
//  topaz
//
//  Created by Tanner Silva on 3/17/23.
//

import Foundation
import QuickLMDB
import AsyncHTTPClient

// FRIENDS:
// a user may be considered a friend to the current user if the current user is following them
extension UE {
	class Profiles:ObservableObject {
		static let logger = Topaz.makeDefaultLogger(label:"db.profile")
		enum Databases:String {
			case profile_main = "_profiles-core"
		}
		
		private let pubkey:String
		let env:QuickLMDB.Environment
		fileprivate let decoder:JSONDecoder
		
		let profilesDB:Database  // [String:Profile] where the key is the pubkey
		
		@MainActor @Published var currentUserProfile:nostr.Profile?
		@MainActor @Published var currentUserProfilePicture:nostr.Profile?
		
		init(pubkey:String, _ env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
			let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
			self.env = env
			let pdb = try env.openDatabase(named:Databases.profile_main.rawValue, flags:[.create], tx:subTrans)
			let decoder = JSONDecoder()
			do {
				let myProfile = try pdb.getEntry(type:Data.self, forKey:pubkey, tx:subTrans)!
				let decoded = try decoder.decode(nostr.Profile.self, from:myProfile)
				_currentUserProfile = Published(wrappedValue:decoded)
			} catch LMDBError.notFound {
				_currentUserProfile = Published(wrappedValue:nil)
			}
			
			self.profilesDB = pdb
			self.decoder = decoder
			self.pubkey = pubkey
			try subTrans.commit()
		}

		/// gets a profile from the database
		func getPublicKeys(publicKeys:Set<String>, tx someTrans:QuickLMDB.Transaction) throws -> [String:nostr.Profile] {
			let getCursor = try self.profilesDB.cursor(tx:someTrans)
			var profiles = [String:nostr.Profile]()
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
		func setPublicKeys(_ profiles:[String:nostr.Profile], tx someTrans:QuickLMDB.Transaction) throws {
			let newTrans = try QuickLMDB.Transaction(self.env, readOnly:false, parent:someTrans)
			let encoder = JSONEncoder()
			let profileCursor = try self.profilesDB.cursor(tx:newTrans)
//			let myExistingImageURL:String?
//			do {
//				myExistingImageURL = try
//			} catch LMDBError.notFound {
//				myExistingImageURL = nil
//			}
			for (pubkey, curProfile) in profiles {
				UE.Profiles.logger.info("writing info for profile", metadata:["pubkey":"\(pubkey)"])
				let encoded = try encoder.encode(curProfile)
				try profileCursor.setEntry(value:encoded, forKey:pubkey)
			}
			if let hasMyProfile = profiles[pubkey] {
				Task.detached { @MainActor [weak self, myprof = hasMyProfile] in
					guard let self = self else { return }
					self.currentUserProfile = myprof
				}
//				Task.detached { [weak self, curURL = hasMyProfile.picture] in
//					guard let self = self else { return }
//					let newClient = try HTTPClient(eventLoopGroupProvider:.shared(Topaz.defaultPool), configuration:HTTPClient.Configuration(timeout:HTTPClient.Configuration.Timeout(connect:.seconds(10), read:.seconds(30))))
//					defer {
//						try? newClient.syncShutdown()
//					}
//					var buildRequest = HTTPClient.Request(url:curURL, method:.GET)
//				}
			}
			try newTrans.commit()
		}
	}
}
