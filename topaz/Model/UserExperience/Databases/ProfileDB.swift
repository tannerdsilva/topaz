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
		
		let profilesDB:Database  // [nostr.Key:Profile] where the key is the pubkey
		
		@MainActor @Published var currentUserProfile:nostr.Profile?
		
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


extension UE.Profiles {
	class PictureDB {
		enum Databases:String {
			case pubkey_picURLHash = "_profile_pic:pubkey-picURLHash"
			case pubkey_picCacheMode = "_profile_pic:pubkey-picCacheMode"
			case pubkey_picData = "_profile_pic:pubkey-picData"
			case pubkey_picDate = "_profile_pic:pubkey-picDate"
			case pubkey_contentType = "_profile_pic:pubkey-contentType"
		}
		
		// the cache policy for a given profile picture
		enum CacheMode:UInt8, MDB_convertible {
			case asNeeded
			case always
		}

		let env:QuickLMDB.Environment
		let pubkey:String

		// the URL hash is the hash of the URL of the picture. this is used to determine if the picture has changed
		let picURLHashDB:Database		// [String:String]

		// the storage policy for the picture.
		let picCacheModeDB:Database		// [String:CacheMode]

		// the picture data is the actual picture data
		let picDataDB:Database			// [String:Data]

		// the picture date is the date the picture was last updated
		let picDateDB:Database			// [String:Date]

		// the content type is the content type of the picture
		let picContentTypeDB:Database	// [String:String]

		private let holder:Holder<(pubkey:String, imageData:Data)>

		// creates a new picture database
		init(myPubkey:String, env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
			let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
			self.env = env
			self.pubkey = myPubkey
			self.picURLHashDB = try env.openDatabase(named:Databases.pubkey_picURLHash.rawValue, flags:[.create], tx:subTrans)
			self.picCacheModeDB = try env.openDatabase(named:Databases.pubkey_picCacheMode.rawValue, flags:[.create], tx:subTrans)
			self.picDataDB = try env.openDatabase(named:Databases.pubkey_picData.rawValue, flags:[.create], tx:subTrans)
			self.picDateDB = try env.openDatabase(named:Databases.pubkey_picDate.rawValue, flags:[.create], tx:subTrans)
			self.picContentTypeDB = try env.openDatabase(named:Databases.pubkey_contentType.rawValue, flags:[.create], tx:subTrans)
			self.holder = Holder<(pubkey:String, imageData:Data)>(holdInterval:0.5)
			try subTrans.commit()
		}

		// assigns a picture to a user. if the user already has a picture, it will be deleted and the new URL will be assigned
		func setImageURLs(_ pk_url:[String:String], tx someTrans:QuickLMDB.Transaction) throws {
			let newTrans = try QuickLMDB.Transaction(self.env, readOnly:false, parent:someTrans)
			let urlHashCursor = try self.picURLHashDB.cursor(tx:newTrans)
			for (pubkey, url) in pk_url {
				try url.asMDB_val({ newURLVal in
					do {
						// check if there is already a URL for this pubkey
						let oldURL = try urlHashCursor.getEntry(.set, key:url).value
						if oldURL != newURLVal {
							// the URL is different, so we need to delete the old picture for this pubkey.
							// the data may not exist, and that is ok
							do {
								// try to delete the picture data
								try self.picDataDB.deleteEntry(key:pubkey, tx:newTrans)
							} catch LMDBError.notFound {}
							do {
								// try to delete the picture date
								try self.picDateDB.deleteEntry(key:pubkey, tx:newTrans)
							} catch LMDBError.notFound {}
							do {
								// try to delete the picture content type
								try self.picContentTypeDB.deleteEntry(key:pubkey, tx:newTrans)
							} catch LMDBError.notFound {}

							// no need to replace or otherwise modify the cache policy entry, so that is left alone

							try urlHashCursor.setEntry(value:newURLVal, forKey:pubkey)
						}
					} catch LMDBError.notFound {
						// new entries get a default cache mode
						try urlHashCursor.setEntry(value:newURLVal, forKey:pubkey)
						try urlHashCursor.setEntry(value:CacheMode.asNeeded, forKey:pubkey)
					}
				})
			}
			try newTrans.commit()
		}

		func getImageOrFetchIfNecessary(_ publicKeys:Set<String>, tx someTrans:QuickLMDB.Transaction) throws -> [String:ImageModel] {
			let imageDataCursor = try self.picDataDB.cursor(tx:someTrans)
			let contentTypeCursor = try self.picContentTypeDB.cursor(tx:someTrans)
			var hasData = [String:(Data, String?)]()
			var needsLoading = Set<String>()
			for curID in publicKeys {
				do {
					let getImage = Data(try imageDataCursor.getEntry(.set, key:curID).value)!
					let getContentType = String(try contentTypeCursor.getEntry(.set, key:curID).value)
					hasData[curID] = (getImage, getContentType)
				} catch LMDBError.notFound {
					// launch an async task to get the image
					let newModel = ImageModel("", state:.noData)
				}
			}
			return [String:ImageModel]()
		}
	}
}
