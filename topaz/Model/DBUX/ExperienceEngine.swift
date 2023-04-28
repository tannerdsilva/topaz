//
//  UserExperience.swift
//  topaz
//
//  Created by Tanner Silva on 4/11/23.
//

import class QuickLMDB.Environment
import struct CLMDB.MDB_dbi
import struct Darwin.size_t
import struct Foundation.URL
import class QuickLMDB.Transaction

protocol Based {
	var base:URL { get }
}
protocol ExperienceEngine: Based {
	associatedtype NotificationType: Hashable
	static var name: String { get }
	static var deltaSize: size_t { get }
	static var maxDBs: MDB_dbi { get }
	static var env_flags: QuickLMDB.Environment.Flags { get }
	var dispatcher: Dispatcher<NotificationType> { get }
	var env: QuickLMDB.Environment { get }
	var pubkey: nostr.Key { get }
	init(base: URL, env: QuickLMDB.Environment, publicKey: nostr.Key, dispatcher:Dispatcher<NotificationType>) throws
}

protocol SharedExperienceEngine {
	associatedtype NotificationType: Hashable
	static var env_flags: QuickLMDB.Environment.Flags { get }
	var dispatcher: Dispatcher<NotificationType> { get }
	var env: QuickLMDB.Environment { get }
	var pubkey: nostr.Key { get }
	init(env: QuickLMDB.Environment, publicKey: nostr.Key, dispatcher:Dispatcher<NotificationType>) throws
}


extension ExperienceEngine {
	/// opens a new transaction for the user environment
	func transact(readOnly:Bool) throws -> QuickLMDB.Transaction {
		return try QuickLMDB.Transaction(self.env, readOnly:readOnly)
	}
}
