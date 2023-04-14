//
//  EventsEngine.swift
//  topaz
//
//  Created by Tanner Silva on 4/13/23.
//

import Foundation
import QuickLMDB
import struct CLMDB.MDB_dbi
import SwiftBlake2
import Logging
import AsyncAlgorithms

extension DBUX {
	class EventsDB:ObservableObject, ExperienceEngine {
		static let name = "event-engine.mdb"
		static let deltaSize = size_t(35e10)
		static let maxDBs:MDB_dbi = 1
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let base:URL
		let env:QuickLMDB.Environment
		let pubkey:nostr.Key
		let logger:Logger
		
		enum Databases:String {
			case events = "dateuid-event"
		}
		
		let encoder = JSONEncoder()
		
		let kindDB:KindDB

		let eventDB_core:Database

		required init(base:URL, env:QuickLMDB.Environment, publicKey:nostr.Key) throws {
			self.base = base
			self.env = env
			self.pubkey = publicKey
			self.logger = try Topaz.makeDefaultLogger(label:"event-engine.mdb")
			self.kindDB = try Topaz.launchExperienceEngine(KindDB.self, from:base.deletingLastPathComponent(), for:pubkey)
			let someTrans = try Transaction(env, readOnly:false)
			self.eventDB_core = try env.openDatabase(named:Databases.events.rawValue, flags:[.create], tx:someTrans)
			try someTrans.commit()
		}

		func writeEvents(_ events:Set<nostr.Event>, tx someTrans:QuickLMDB.Transaction) throws {
			let subTrans = try Transaction(env, readOnly:false, parent: someTrans)
			let eventCursor = try self.eventDB_core.cursor(tx:subTrans)
			try kindDB.setEvent(Set(events), tx:subTrans)
			for curEvent in events {
				let encodedData = try encoder.encode(curEvent)
				try eventCursor.setEntry(value:encodedData, forKey:curEvent.keySignature)
			}
			try subTrans.commit()
		}

		func getEvents(limit:UInt64 = 50, tx someTrans:QuickLMDB.Transaction) throws -> [nostr.Event] {
			let cursor = try self.eventDB_core.cursor(tx:someTrans)
			var buildEvents = [nostr.Event]()
			for (_, curEvent) in cursor.reversed() {
				buildEvents.append(try JSONDecoder().decode(nostr.Event.self, from:Data(curEvent)!))
				if buildEvents.count > limit {
					return buildEvents
				}
			}
			return buildEvents
		}
		
		func getEvent(limit:UInt64 = 50, kind:nostr.Event.Kind, tx someTrans:QuickLMDB.Transaction) throws -> [nostr.Event] {
			let kindFilter:KindDB.Filter
			do {
				kindFilter = try self.kindDB.getKindFilter(kind:kind, tx:someTrans)
			} catch LMDBError.notFound {
				return [nostr.Event]()
			}
			let cursor = try self.eventDB_core.cursor(tx:someTrans)
			var buildEvents = [nostr.Event]()
			let decoder = JSONDecoder()
			for (keySig, curEvent) in cursor.reversed() {
				if try kindFilter.shouldInclude(keySig) == true {
					buildEvents.append(try decoder.decode(nostr.Event.self, from:Data(curEvent)!))
					if buildEvents.count >= limit {
						return buildEvents
					}
				}
			}
			return buildEvents
		}

		struct DateIDDB:ExperienceEngine {
			static let name = "event-engine-date-id.mdb"
			static let deltaSize = size_t(35e10)
			static let maxDBs:MDB_dbi = 2
			static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
			let base:URL
			let env:QuickLMDB.Environment
			let pubkey:nostr.Key
			let logger:Logger
			enum Databases:String {
				case date_uid = "date-uid"
				case uid_date = "uid-date"
			}

			// stores the given UIDs that are associated with the given date
			let date_uid:Database	// [DBUX.Date:nostr.Event.UID]
			// stores the date associated with the given UID
			let uid_date:Database	// [nostr.Event.UID:DBUX.Date]

			init(base:URL, env:QuickLMDB.Environment, publicKey:nostr.Key) throws {
				self.base = base
				self.env = env
				self.pubkey = publicKey
				self.logger = Topaz.makeDefaultLogger(label:"event-engine-date-id.mdb")
				let someTrans = try Transaction(env, readOnly:false)
				self.date_uid = try env.openDatabase(named:Databases.date_uid.rawValue, flags:[.create, .dupSort], tx:someTrans)
				self.uid_date = try env.openDatabase(named:Databases.uid_date.rawValue, flags:[.create, .dupSort], tx:someTrans)
				try someTrans.commit()
			}

			func set(events:Set<nostr.Event>, tx someTrans:QuickLMDB.Transaction) throws {
				let subTrans = try Transaction(env, readOnly:false, parent: someTrans)
				let dateUCursor = try self.date_uid.cursor(tx:subTrans)
				let uidDCursor = try self.uid_date.cursor(tx:subTrans)
				for event in events {
					try dateUCursor.setEntry(value:event.uid, forKey:event.created)
					try uidDCursor.setEntry(value:event.created, forKey:event.uid)
				}
				try subTrans.commit()
			}
		}

		struct KindDB:ExperienceEngine {
			static let name = "event-engine-kind-id.mdb"
			static let deltaSize = size_t(35e10)
			static let maxDBs:MDB_dbi = 2
			static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
			let base:URL
			let env:QuickLMDB.Environment
			let pubkey:nostr.Key
			
			struct Filter {
				let cursor:QuickLMDB.Cursor
				let kind:nostr.Event.Kind
				init(_ kind_keysig:Database, kind:nostr.Event.Kind, tx someTrans:QuickLMDB.Transaction) throws {
					let makeCursor = try kind_keysig.cursor(tx:someTrans)
					try makeCursor.getEntry(.set, key:kind)
					self.cursor = makeCursor
					self.kind = kind
				}
				
				func shouldInclude<D>(_ keysig:D) throws -> Bool where D:MDB_encodable {
					do {
						try cursor.getEntry(.getBoth, key:kind, value:keysig)
						return true
					} catch LMDBError.notFound {
						return false
					}
				}
			}
			
			func getKindFilter(kind:nostr.Event.Kind, tx someTrans:QuickLMDB.Transaction) throws -> Filter {
				return try Filter(self.kind_uid, kind:kind, tx:someTrans)
			}
			
			enum Databases:String {
				case kind_uid = "kind-uid"
				case uid_kind = "uid-kind"
			}

			let logger:Logger

			// stores the given UIDs that are associated with the given kind
			let kind_uid:Database
			// stores the kind associated with the given UID
			let uid_kind:Database

			init(base:URL, env:QuickLMDB.Environment, publicKey:nostr.Key) throws {
				self.base = base
				self.env = env
				self.pubkey = publicKey
				self.logger = try Topaz.makeDefaultLogger(label:"event-engine.mdb")
				let someTrans = try Transaction(env, readOnly:false)
				self.kind_uid = try env.openDatabase(named:Databases.kind_uid.rawValue, flags:[.create, .dupSort], tx:someTrans)
				self.uid_kind = try env.openDatabase(named:Databases.uid_kind.rawValue, flags:[.create, .dupSort], tx:someTrans)
				try someTrans.commit()
			}

			/// bulk import events into the database
			/// - for each public key, the event kinds will attempt to be assigned
			/// - will NOT overwrite existing data if the specified public key is already in the database
			/// - will NOT throw ``LMDBError.keyExists`` if the public key is already in the database with the same kind
			func setEvent(_ events:Set<nostr.Event>, tx someTrans:QuickLMDB.Transaction) throws {
				let subTrans = try Transaction(env, readOnly:false, parent: someTrans)
				let uidKCursor = try self.uid_kind.cursor(tx:subTrans)
				let kUIDCursor = try self.kind_uid.cursor(tx:subTrans)
				for event in events {
					do {
						try uidKCursor.setEntry(value:event.kind, forKey:event.keySignature, flags:[.noOverwrite])
					} catch LMDBError.keyExists {
						// throw an error if the key already exists and the value is not the same
						guard nostr.Event.Kind(rawValue:Int(try uidKCursor.getEntry(.set, key:event.keySignature).value)!) == event.kind else {
							throw LMDBError.keyExists
						}
						continue
					}
					try kUIDCursor.setEntry(value:event.keySignature, forKey:event.kind)
				}
				try subTrans.commit()
				self.logger.debug("successfully installed events.", metadata:["count": "\(events.count)"])
			}

			/// get all kinds for a given uid
			/// - never throws LMDBError.notFound
			func getKinds(keySigs:Set<String>, tx someTrans:QuickLMDB.Transaction) throws -> [String:nostr.Event.Kind] {
				let uidKCursor = try self.uid_kind.cursor(tx:someTrans)
				var ret = [String:nostr.Event.Kind]()
				for uid in keySigs {
					ret[uid] = nostr.Event.Kind(rawValue:Int(try uidKCursor.getEntry(.set, key:uid).value)!)
				}
				return ret
			}

			/// removes the given uids from the database
			func deleteEvents(keySigs:Set<String>, tx someTrans:QuickLMDB.Transaction? = nil) throws {
				let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
				let uidKCursor = try self.uid_kind.cursor(tx:subTrans)
				let kindUIDCursor = try self.kind_uid.cursor(tx:subTrans)
				for curID in keySigs {
					let getKind = try uidKCursor.getEntry(.set, key:curID).value
					let asKind = nostr.Event.Kind(getKind)!
					try kindUIDCursor.getEntry(.getBoth, key:asKind, value:curID)
					try kindUIDCursor.deleteEntry()
					try uidKCursor.deleteEntry()
				}
				try subTrans.commit()
				self.logger.debug("successfully deleted events.", metadata:["count": "\(keySigs.count)"])
			}
		}
	}
}
