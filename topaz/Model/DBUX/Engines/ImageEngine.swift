//
//  ImageEngine.swift
//  topaz
//
//  Created by Tanner Silva on 4/27/23.
//

import QuickLMDB
import struct CLMDB.MDB_dbi
import Logging
import struct Foundation.URL
import struct Foundation.size_t
import struct Foundation.Data
import func Foundation.ceil

extension DBUX {
	final class ProfileImageStore:DBUX.AssetStore, ExperienceEngine {
		static let name = "profile-imagestore"
		static let deltaSize = SizeMode.fixed(size_t(2.56e+8))
	}
}

extension DBUX {
	class AssetStore {
		struct Hit {
			let urlHash:DBUX.URLHash
			let date:DBUX.Date
		}
		typealias NotificationType = DBUX.Notification
		static let maxDBs:MDB_dbi = 2
		static let env_flags:QuickLMDB.Environment.Flags = [.noSync]
		let dispatcher: Dispatcher<DBUX.Notification>
		
		enum Databases:String {
			case assetData = "asset_data"
			case cacheTimestamp = "asset_cachedOn"
		}
		var base:URL
		let env:QuickLMDB.Environment
		let pubkey:nostr.Key
		let logger:Logger
		let assetData: Database
		let cacheTimestamp: Database
		private let hits:HitCounter // the hit counter allows topaz to be more intelligent on which cached assets it should keep vs which should be purged when the memorymap limit is reached
		let holder:Holder<AssetStore.Hit>
		required init(base: URL, env environment:QuickLMDB.Environment, keyPair: nostr.KeyPair, dispatcher:Dispatcher<NotificationType>) throws {
			self.env = environment
			self.logger = Topaz.makeDefaultLogger(label:"asset-engine_\(String(describing:type(of:Self.self))).mdb")
			let newTrans = try Transaction(environment, readOnly:false)
			self.assetData = try environment.openDatabase(named:Databases.assetData.rawValue, flags:[.create], tx:newTrans)
			self.cacheTimestamp = try environment.openDatabase(named:Databases.cacheTimestamp.rawValue, flags:[.create], tx:newTrans)
			try newTrans.commit()
			self.dispatcher = dispatcher
			self.base = base
			self.pubkey = keyPair.pubkey
			let hitstore = try Topaz.launchExperienceEngine(HitCounter.self, from:base, for:keyPair, dispatcher:dispatcher)
			let hitHolder = hitstore.hitHolder
			self.holder = hitHolder
			self.hits = hitstore
		}
		
		// commits an asset to the database. any previous data will not
		func storeAsset(_ data:Data, for url:DBUX.URLHash) throws {
			let masterTrans = try Transaction(self.env, readOnly:false)
			do {
				let writeTrans = try Transaction(self.env, readOnly:false, parent:masterTrans)
				do {
					try assetData.setEntry(value:data, forKey:url, tx:writeTrans)
					try cacheTimestamp.setEntry(value:DBUX.Date(), forKey:url, tx:writeTrans)
					self.logger.info("successfully stored asset.")
					try writeTrans.commit()
				} catch let error {
					writeTrans.abort()
					throw error
				}
			} catch LMDBError.mapFull {
				
				self.logger.info("memorymap full - removing least popular")
				// pull the least popular items from the database
				let deleteTrans = try Transaction(self.env, readOnly:false, parent:masterTrans)
				try self.removeLeastPopular(0.25, tx:deleteTrans)
				try deleteTrans.commit()
				
				// write the data again (hope this doesn't throw otherwise we're fucked lmfao)
				let writeTrans = try Transaction(self.env, readOnly:false, parent:masterTrans)
				try assetData.setEntry(value:data, forKey:url, tx:writeTrans)
				self.logger.info("successfully stored asset.")
				try writeTrans.commit()
			}
			try masterTrans.commit()
		}
		
		func getAsset(_ url:DBUX.URLHash) async throws -> Data {
			return try await withUnsafeThrowingContinuation({ (myCont:UnsafeContinuation<Data, Swift.Error>) in
				do {
					let readTransaction = try Transaction(self.env, readOnly:true)
					let getData = try self.assetData.getEntry(type:Data.self, forKey:url, tx:readTransaction)!
					try readTransaction.commit()
					myCont.resume(returning:getData)
				} catch let error {
					myCont.resume(throwing: error)
				}
			})
		}
		
		// removes the least popular entries from the databse based on a specified reduction factor
		func removeLeastPopular(_ fraction:Double, tx someTrans:QuickLMDB.Transaction? = nil) throws {
			let newTrans = try Transaction(self.env, readOnly:false, parent:someTrans)
			let totalAssetCount = try self.assetData.getStatistics(tx:newTrans).entries
			let assetCursor = try self.assetData.cursor(tx:newTrans)
			let dateCursor = try self.cacheTimestamp.cursor(tx:newTrans)
			guard totalAssetCount > 0 else {
				return
			}
			var buildItems = Array<DBUX.URLHash>()
			let nowDate = DBUX.Date()
			for (curItem, _) in assetCursor {
				let asHash = DBUX.URLHash(curItem)
				let cachedDate = DBUX.Date(try dateCursor.getEntry(.set, key:curItem).value)!
				// items that are less than 30 seconds old are exempt from purging
				if cachedDate.timeIntervalSince(nowDate) < -30 {
					buildItems.append(asHash)
				}
			}
			let itemsToDrop = try hits.trimUnpopularEntries(presortedEntries:buildItems, by:0.25, tx:newTrans)
			for curItem in itemsToDrop {
				do {
					try assetCursor.getEntry(.set, key:curItem)
					try dateCursor.getEntry(.set, key:curItem)
					try assetCursor.deleteEntry()
					try dateCursor.deleteEntry()
				} catch LMDBError.notFound {}
			}
			try newTrans.commit()
		}
		
		private class HitCounter:ExperienceEngine {
			let base:URL
			typealias NotificationType = DBUX.Notification
			static var name = "hits.mdb"
			static var deltaSize = SizeMode.relativeGrowth(size_t(1.5e+7))
			static var maxDBs:MDB_dbi = 2
			static var env_flags:QuickLMDB.Environment.Flags = [.noSubDir]
			let dispatcher: Dispatcher<DBUX.Notification>
			let env: QuickLMDB.Environment
			let pubkey: nostr.Key
			
			enum Databases: String {
				case image_hash_dates = "image-hash-dates"
			}
			
			let logger: Logger
			
			// Stores the access dates associated with the given image hash
			let asset_hash_dates:Database
			
			let hitHolder = Holder<AssetStore.Hit>(holdInterval:2)
			var consumeTask:Task<Void, Never>? = nil
			required init(base: URL, env environment:QuickLMDB.Environment, keyPair:nostr.KeyPair, dispatcher:Dispatcher<NotificationType>) throws {
				self.dispatcher = dispatcher
				self.base = base
				self.env = environment
				self.pubkey = keyPair.pubkey
				self.logger = Topaz.makeDefaultLogger(label: "image-hit-counter.mdb")
				let someTrans = try Transaction(env, readOnly: false)
				self.asset_hash_dates = try env.openDatabase(named: Databases.image_hash_dates.rawValue, flags: [.create, .dupSort], tx: someTrans)
				try self.asset_hash_dates.setDupsortCompare(tx:someTrans, DBUX.Date.mdbCompareFunction)
				try someTrans.commit()
				self.consumeTask = Task.detached { [weak self, hol = hitHolder] in
					try? await withTaskCancellationHandler(operation: { [weak self, hol = hol] in
						for await curHits in hol {
							guard let self = self else { return }
							try self.env.transact(readOnly:false) { someTrans in
								for curHit in curHits {
									try self.addHit(assetHash:curHit.urlHash, accessDate:curHit.date, tx:someTrans)
								}
							}
						}
					}, onCancel: { [hol = hol] in
						Task.detached { [hol = hol] in
							await hol.finish()
						}
					})
				}
			}
			
			// adds a hit to the image hash with the given access date
			fileprivate func addHit(assetHash:DBUX.URLHash, accessDate:DBUX.Date, tx someTrans: QuickLMDB.Transaction) throws {
				do {
					let subTrans = try Transaction(env, readOnly: false, parent: someTrans)
					let ahdCursor = try self.asset_hash_dates.cursor(tx: subTrans)
					try ahdCursor.setEntry(value: accessDate, forKey: assetHash)
					try subTrans.commit()
					self.logger.debug("successfully added asset hit.", metadata: ["accessDate": "\(accessDate)"])
				} catch LMDBError.mapFull {
					try self.reduceDateCount(by:0.35, tx:someTrans)
					// now try to write again
					let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
					let ahdCursor = try self.asset_hash_dates.cursor(tx: subTrans)
					try ahdCursor.setEntry(value: accessDate, forKey: assetHash)
					try subTrans.commit()
				}
			}
			
			// determines which entries are the least popular and removes them from the database. these values are returned
			fileprivate func trimUnpopularEntries(presortedEntries:[DBUX.URLHash], by reductionFactor:Double, tx someTrans:QuickLMDB.Transaction) throws -> [DBUX.URLHash] {
				let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
				let ahdCursor = try self.asset_hash_dates.cursor(tx:subTrans)
				var buildAllCounts = [DBUX.URLHash:size_t]()
				for curEntry in presortedEntries {
					do {
						let _ = try ahdCursor.getEntry(.set, key:curEntry)
						let count = try ahdCursor.dupCount()
						buildAllCounts[curEntry] = count
					} catch LMDBError.notFound {
						buildAllCounts[curEntry] = 0
					}
				}
				let sortedCounts = buildAllCounts.sorted(by: { $0.value < $1.value })
				let reduceCount = Int(ceil(Double(presortedEntries.count) * (1 - reductionFactor)))
				let deleteItems = Array(sortedCounts.prefix(reduceCount))
				for curItem in deleteItems {
					try ahdCursor.getEntry(.set, key:curItem.key)
					try ahdCursor.deleteEntry(flags:[.noDupData])
				}
				try subTrans.commit()
				return deleteItems.compactMap( { $0.key })
			}
			
			// reduces the amount of dates on each entry by a specified (proportional) reduction factor
			fileprivate func reduceDateCount(by reductionFactor:Double, tx someTrans:QuickLMDB.Transaction) throws {
				let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
				let ahdCursor = try self.asset_hash_dates.cursor(tx:subTrans)
				do {
					var curEntry = try ahdCursor.getEntry(.first)
					repeat {
						let assetHash = curEntry.key
						var dates = [DBUX.Date]()
						for (_, value) in try ahdCursor.makeDupIterator(key: assetHash) {
							dates.append(DBUX.Date(value)!)
						}

						let reducedCount = Int(Double(dates.count) * (1 - reductionFactor))
						let sortedDates = dates.sorted()
						let reducedDates = Array(sortedDates.prefix(reducedCount))

						try ahdCursor.deleteEntry(flags:[.noDupData])

						for date in reducedDates.sorted() {
							try ahdCursor.setEntry(value: date, forKey: assetHash)
						}

						curEntry = try ahdCursor.getEntry(.nextNoDup)
					} while true
				} catch LMDBError.notFound {}
				try subTrans.commit()
			}
			
			// use this function to assure that a set of hashes are removed from the database
			fileprivate func deleteAssets(_ hashes:Set<DBUX.URLHash>, tx someTrans:QuickLMDB.Transaction) throws {
				let sorted = hashes.sorted()
				let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
				let ahdCursor = try self.asset_hash_dates.cursor(tx:subTrans)
				for curHash in sorted {
					do {
						try ahdCursor.getEntry(.set, key:curHash)
						try ahdCursor.deleteEntry(flags:[.noDupData])
					} catch LMDBError.notFound {}
				}
				try subTrans.commit()
			}
		}
	}
}
	
