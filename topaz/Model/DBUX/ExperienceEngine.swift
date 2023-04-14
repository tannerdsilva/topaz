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

protocol Based {
	var base:URL { get }
}
protocol ExperienceEngine:Based {
	static var name:String { get }
	static var deltaSize:size_t { get }
	static var maxDBs:MDB_dbi { get }
	static var env_flags:QuickLMDB.Environment.Flags { get }
	var env:QuickLMDB.Environment { get }
	var pubkey:nostr.Key { get }
	init(base:URL, env:QuickLMDB.Environment, publicKey:nostr.Key) throws
	// static func create(base:URL, env:QuickLMDB.Environment, keypair:KeyPair) throws -> Self
}
