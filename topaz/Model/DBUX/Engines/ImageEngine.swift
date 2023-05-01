//
//  ImageEngine.swift
//  topaz
//
//  Created by Tanner Silva on 4/27/23.
//

import Foundation
import QuickLMDB
import struct CLMDB.MDB_dbi
import Logging
import UIKit

class ImageCache:ExperienceEngine {
	struct Hit {
		let urlHash:DBUX.URLHash
		let date:DBUX.Date
	}
	typealias NotificationType = DBUX.Notification
	static let name = "image-engine.mdb"
	static let deltaSize = SizeMode.fixed(size_t(5.12e+8))
	static let maxDBs:MDB_dbi = 2
	static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
	let dispatcher: Dispatcher<DBUX.Notification>
	
	enum Databases:String {
		case imageData
		case cacheTimestamp
	}
	
	var base:URL
	let env:QuickLMDB.Environment
	let pubkey:nostr.Key
	let logger:Logger
	let imageData: Database
	let cacheTimestamp: Database
	fileprivate let imageHitCounter: ImageHitCounter
	
	required init(base: URL, env environment:QuickLMDB.Environment, publicKey: nostr.Key, dispatcher:Dispatcher<NotificationType>) throws {
		self.env = environment
		self.logger = Topaz.makeDefaultLogger(label:"image-db")
		let newTrans = try Transaction(environment, readOnly:false)
		self.imageData = try environment.openDatabase(named:Databases.imageData.rawValue, flags:[.create], tx:newTrans)
		self.cacheTimestamp = try environment.openDatabase(named:Databases.cacheTimestamp.rawValue, flags:[.create], tx:newTrans)
		try newTrans.commit()
		self.dispatcher = dispatcher
		self.base = base
		self.pubkey = publicKey
		self.imageHitCounter = try Topaz.launchExperienceEngine(ImageHitCounter.self, from:base.deletingLastPathComponent(), for: publicKey, dispatcher: dispatcher)
	}
	
	func removeImages(urls:Set<DBUX.URLHash>) throws -> Void {
		let transaction = try Transaction(env, readOnly:false)
		let dataCursor = try imageData.cursor(tx:transaction)
		let cacheTimestamp = try cacheTimestamp.cursor(tx:transaction)
		for curURL in urls.sorted() {
			try dataCursor.getEntry(.set, key:curURL)
			try cacheTimestamp.getEntry(.set, key:curURL)
			try dataCursor.deleteEntry()
			try cacheTimestamp.deleteEntry()
		}
		try transaction.commit()
	}

	func cachedImage(for url: URL) throws -> UIImage? {
		let hash = try DBUX.URLHash(url.absoluteString)
		let transaction = try Transaction(env, readOnly: true)
		let imageDataCursor = try imageData.cursor(tx: transaction)
		guard let data = try? imageDataCursor.getEntry(.set, key: hash).value else {
			return nil
		}
		return UIImage(data: Data(data))
	}

	func loadImage(from url: URL, using contentTypeAndDataFunction: (URL) async throws -> (String, Data), catchFull:Bool = true) async throws -> UIImage {
		if let cachedImage = try cachedImage(for: url) {
			return cachedImage
		}

		let (contentType, data) = try await contentTypeAndDataFunction(url)
		guard let image = UIImage(data: data), contentType.starts(with: "image/") else {
			throw NSError(domain: "Invalid image data or content type", code: -1, userInfo: nil)
		}
		
		let resizedImage = image.resizedAndCompressedImage(maxPixelsInLargestDimension:1200, compressionQuality:0.4)!

		let hash = try DBUX.URLHash(url.absoluteString)
		func writeData() throws -> UIImage {
			let transaction = try Transaction(env, readOnly: false)
			let imageDataCursor = try imageData.cursor(tx: transaction)
			if let hasData = resizedImage.exportData() {
				let cacheTimestampCursor = try cacheTimestamp.cursor(tx: transaction)
				
				try imageDataCursor.setEntry(value:hasData, forKey: hash)
				try cacheTimestampCursor.setEntry(value:DBUX.Date(), forKey: hash)

				try transaction.commit()
				logger.info("successfully cached image.", metadata: ["url": "\(url.absoluteString)"])
				return image
			} else {
				throw NSError(domain: "Data export error", code: -1, userInfo: nil)
			}
		}
		do {
			return try writeData()
		} catch LMDBError.mapFull {
			if (catchFull == true) {
				let hitTrans = try imageHitCounter.transact(readOnly:false)
				let removeHits = try self.imageHitCounter.deleteAndReturnLeastPopularURLs(since:DBUX.Date().addingTimeInterval(-1.296e6), tx: hitTrans)
				try hitTrans.commit()
				try self.removeImages(urls:removeHits)
				return try writeData()
			} else {
				throw LMDBError.mapFull
			}
		}
	}
}

fileprivate class ImageHitCounter: ExperienceEngine {
	let base: URL
	typealias NotificationType = DBUX.Notification
	static let name = "image-hit-engine.mdb"
	static let deltaSize = SizeMode.fixed(size_t(1e+7)) // 10MB
	static let maxDBs:MDB_dbi = 1
	static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir]
	let dispatcher: Dispatcher<DBUX.Notification>
	
	let env: QuickLMDB.Environment
	let pubkey: nostr.Key
	
	enum Databases: String {
		case image_hash_dates = "image-hash-dates"
	}
	
	let logger: Logger
	
	// Stores the access dates associated with the given image hash
	let image_hash_dates:Database
	
	let hitHolder = Holder<ImageCache.Hit>(holdInterval:2)
	var consumeTask:Task<Void, Never>? = nil
	
	required init(base: URL, env environment:QuickLMDB.Environment, publicKey: nostr.Key, dispatcher:Dispatcher<NotificationType>) throws {
		self.dispatcher = dispatcher
		self.base = base
		self.env = environment
		self.pubkey = publicKey
		self.logger = Topaz.makeDefaultLogger(label: "image-hit-counter.mdb")
		let someTrans = try Transaction(env, readOnly: false)
		self.image_hash_dates = try env.openDatabase(named: Databases.image_hash_dates.rawValue, flags: [.create, .dupSort], tx: someTrans)
		try self.image_hash_dates.setDupsortCompare(tx:someTrans, DBUX.Date.mdbCompareFunction)
		try someTrans.commit()
		self.consumeTask = Task.detached { [weak self, hol = hitHolder] in
			try? await withTaskCancellationHandler(operation: { [weak self, hol = hol] in
				for await curHits in hol {
					guard let self = self else { return }
					try self.env.transact(readOnly:false) { someTrans in
						for curHit in curHits {
							try self.addHit(imageHash:curHit.urlHash, accessDate:curHit.date, tx:someTrans)
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
	
	// Adds a hit to the image hash with the given access date
	fileprivate func addHit(imageHash:DBUX.URLHash, accessDate:DBUX.Date, tx someTrans: QuickLMDB.Transaction, catchFull:Bool = true) throws {
		do {
			let subTrans = try Transaction(env, readOnly: false, parent: someTrans)
			let ihdCursor = try self.image_hash_dates.cursor(tx: subTrans)
			try ihdCursor.setEntry(value: accessDate, forKey: imageHash)
			try subTrans.commit()
			self.logger.debug("Successfully added hit.", metadata: ["accessDate": "\(accessDate)"])
		} catch LMDBError.mapFull {
			if (catchFull == true) {
				let subTrans = try Transaction(env, readOnly: false, parent: someTrans)
				try self.reduceDateCount(by:0.3, tx:subTrans)
				try self.addHit(imageHash: imageHash, accessDate:accessDate, tx:someTrans, catchFull:false)
				try subTrans.commit()
			} else {
				throw LMDBError.mapFull
			}
		}
	}
	
	// Prunes access dates older than the specified date for all image hashes
	func pruneDates(olderThan date:DBUX.Date, tx someTrans: QuickLMDB.Transaction) throws {
		let subTrans = try Transaction(env, readOnly: false, parent: someTrans)
		let ihdCursor = try self.image_hash_dates.cursor(tx: subTrans)
		do {
			var curEntry = try ihdCursor.getEntry(.first)
			repeat {
				let imageHash = curEntry.key
				
				var dates = [DBUX.Date]()
				for (_, value) in try ihdCursor.makeDupIterator(key: imageHash) {
					let accessDate = DBUX.Date(value)!
					if accessDate < date {
						try ihdCursor.deleteEntry()
					} else {
						dates.append(accessDate)
					}
				}
				if dates.isEmpty {
					try ihdCursor.deleteEntry(flags:[.noDupData])
				}
				curEntry = try ihdCursor.getEntry(.nextNoDup)
			} while true
		} catch LMDBError.notFound {}
		try subTrans.commit()
		self.logger.debug("Successfully pruned dates older than the specified date.", metadata: ["date": "\(date)"])
	}
	
	// Reduces the date count of every image hash proportionally by a specified reduction factor
	func reduceDateCount(by reductionFactor: Double = 0.4, tx someTrans: QuickLMDB.Transaction) throws {
		let subTrans = try Transaction(env, readOnly: false, parent: someTrans)
		let ihdCursor = try self.image_hash_dates.cursor(tx: subTrans)

		do {
			var curEntry = try ihdCursor.getEntry(.first)
			repeat {
				let imageHash = curEntry.key

				var dates = [DBUX.Date]()
				for (_, value) in try ihdCursor.makeDupIterator(key: imageHash) {
					dates.append(DBUX.Date(value)!)
				}

				let reducedCount = Int(Double(dates.count) * (1 - reductionFactor))
				let sortedDates = dates.sorted()
				let reducedDates = Array(sortedDates.prefix(reducedCount))

				try ihdCursor.deleteEntry(flags:[.noDupData])

				for date in reducedDates.sorted() {
					try ihdCursor.setEntry(value: date, forKey: imageHash)
				}

				curEntry = try ihdCursor.getEntry(.nextNoDup)
			} while true
		} catch LMDBError.notFound {}

		try subTrans.commit()
		self.logger.debug("Successfully reduced date count of every image hash proportionally by \(reductionFactor * 100)%.")
	}
	
	// Deletes all access dates for a given image hash
	func deleteDates(forImageHash imageHash: String, tx someTrans: QuickLMDB.Transaction) throws {
		let subTrans = try Transaction(env, readOnly: false, parent: someTrans)
		let ihdCursor = try self.image_hash_dates.cursor(tx: subTrans)
		try ihdCursor.getEntry(.set, key:imageHash)
		try ihdCursor.deleteEntry(flags:[.noDupData])
		try subTrans.commit()
		self.logger.debug("Successfully deleted dates for the specified image hash.")
	}
	
	// Deletes and returns the least popular 20% of URL hashes based on their access frequency up to a certain date
	func deleteAndReturnLeastPopularURLs(since date: DBUX.Date, percentageToRemove: Double = 0.3, tx someTrans: QuickLMDB.Transaction) throws -> Set<DBUX.URLHash> {
		let subTrans = try Transaction(env, readOnly: false, parent: someTrans)
		let ihdCursor = try self.image_hash_dates.cursor(tx: subTrans)

		var urlAccessCounts = [DBUX.URLHash: Int]()

		do {
			var curEntry = try ihdCursor.getEntry(.first)
			repeat {
				let imageHash = curEntry.key

				var count = 0
				for (_, value) in try ihdCursor.makeDupIterator(key: imageHash) {
					let accessDate = DBUX.Date(value)!
					if accessDate <= date {
						count += 1
					}
				}
				urlAccessCounts[DBUX.URLHash(imageHash)] = count
				curEntry = try ihdCursor.getEntry(.nextNoDup)
			} while true
		} catch LMDBError.notFound {}

		let sortedURLs = urlAccessCounts.sorted { $0.value < $1.value }
		let removalCount = Int(Double(sortedURLs.count) * percentageToRemove)
		let urlsToRemove = Set(sortedURLs.prefix(removalCount).map { $0.key })

		for url in urlsToRemove.sorted() {
			try ihdCursor.getEntry(.set, key:url)
			try ihdCursor.deleteEntry()
		}

		try subTrans.commit()
		self.logger.debug("Successfully deleted and returned the least popular \(percentageToRemove * 100)% of URL hashes based on their access frequency up to a certain date.", metadata: ["date": "\(date)"])

		return urlsToRemove
	}

	
	deinit {
		consumeTask?.cancel()
	}
}
