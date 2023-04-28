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
	typealias NotificationType = DBUX.Notification
	static let name = "image-engine.mdb"
	static let deltaSize = size_t(419430400)
	static let maxDBs:MDB_dbi = 3
	static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
	let dispatcher: Dispatcher<DBUX.Notification>
	
	enum Databases:String {
		case imageData
		case cacheTimestamp
		case requestTimestamp
	}
	
	var base:URL
	let env:QuickLMDB.Environment
	let pubkey:nostr.Key
	let logger:Logger
	let imageData: Database
	let cacheTimestamp: Database
	let requestTimestamp: Database

	required init(base: URL, env environment:QuickLMDB.Environment, publicKey: nostr.Key, dispatcher:Dispatcher<NotificationType>) throws {
		self.env = environment
		self.logger = Topaz.makeDefaultLogger(label:"image-db")
		let newTrans = try Transaction(environment, readOnly:false)
		self.imageData = try environment.openDatabase(named:Databases.imageData.rawValue, flags:[.create], tx:newTrans)
		self.cacheTimestamp = try environment.openDatabase(named:Databases.cacheTimestamp.rawValue, flags:[.create], tx:newTrans)
		self.requestTimestamp = try environment.openDatabase(named:Databases.requestTimestamp.rawValue, flags:[.create], tx:newTrans)
		try newTrans.commit()
		self.dispatcher = dispatcher
		self.base = base
		self.pubkey = publicKey
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

	func loadImage(from url: URL, using contentTypeAndDataFunction: (URL) async throws -> (String, Data)) async throws -> UIImage {
		if let cachedImage = try cachedImage(for: url) {
			return cachedImage
		}

		let (contentType, data) = try await contentTypeAndDataFunction(url)
		guard let image = UIImage(data: data), contentType.starts(with: "image/") else {
			throw NSError(domain: "Invalid image data or content type", code: -1, userInfo: nil)
		}

		let hash = try DBUX.URLHash(url.absoluteString)
		let transaction = try Transaction(env, readOnly: false)
		let imageDataCursor = try imageData.cursor(tx: transaction)
		let cacheTimestampCursor = try cacheTimestamp.cursor(tx: transaction)
		let requestTimestampCursor = try requestTimestamp.cursor(tx: transaction)

		try imageDataCursor.setEntry(value:data, forKey: hash)
		try cacheTimestampCursor.setEntry(value:DBUX.Date(), forKey: hash)
		try requestTimestampCursor.setEntry(value:DBUX.Date(), forKey: hash)

		try transaction.commit()
		logger.info("successfully cached image.", metadata: ["url": "\(url.absoluteString)"])

		return image
	}
}
