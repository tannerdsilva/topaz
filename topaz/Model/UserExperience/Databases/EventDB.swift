//
//  EventDB.swift
//  topaz
//
//  Created by Tanner Silva on 3/21/23.
//

import Foundation
import QuickLMDB
import SwiftUI
import Logging
import SwiftBlake2

extension UE {
	class EventsDB:ObservableObject {
		static let logger:Logger = Logger(label:"com.nostr.event.db")
		private static let df = ISO8601DateFormatter()
		static func produceEventSignatureKey(_ event:nostr.Event) throws -> Data {
			let formattedDate = Data(df.string(from: event.created).utf8)
			var eventUIDHash = try Blake2bHasher(outputLength:48)
			try eventUIDHash.update(Data(event.sig.utf8))
			let finalUID = try eventUIDHash.export()
			return formattedDate + finalUID
		}
		
		private struct DateDatabase {
			static let logger:Logger = Logger(label:"com.nostr.event.date")

			enum Databases:String, MDB_convertible {
				case date_uid = "_event_date-uid"	// [Date:String] * DUP *
				case uid_date = "_event_uid-date"	// [String:Date]
			}

			// the environment that this database is associated with
			let env:QuickLMDB.Environment

			// stores the given UIDs that are associated with the given date
			let date_uid:Database
			// stores the date associated with the given UID
			let uid_date:Database

			init(_ env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
				self.env = env
				self.date_uid = try env.openDatabase(named:Databases.date_uid.rawValue, flags:[.create], tx:someTrans)
				self.uid_date = try env.openDatabase(named:Databases.uid_date.rawValue, flags:[.create], tx:someTrans)
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
		private struct KindDatabase {
			static let logger:Logger = Logger(label:"com.nostr.event.kind")
			enum Databases:String, MDB_convertible {
				case uid_kind = "_event_uid-kind"
				case kind_uid = "_event_kind-uid"
			}
			
			struct KindFilter {
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
			
			func getKindFilter(kind:nostr.Event.Kind, tx someTrans:QuickLMDB.Transaction) throws -> KindFilter {
				return try KindFilter(self.kind_uid, kind:kind, tx:someTrans)
			}

			let env:QuickLMDB.Environment

			// * does not allow an override of an existing entry if the values are not the same *
			let uid_kind:Database		// [Data:Kind]
			let kind_uid:Database		// [Kind:Data] * DUP *

			init(_ env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
				self.env = env
				self.uid_kind = try env.openDatabase(named:Databases.uid_kind.rawValue, flags:[.create], tx:someTrans)
				self.kind_uid = try env.openDatabase(named:Databases.kind_uid.rawValue, flags:[.create, .dupSort], tx:someTrans)
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
				Self.logger.debug("successfully installed events.", metadata:["count": "\(events.count)"])
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
				Self.logger.debug("successfully deleted events.", metadata:["count": "\(keySigs.count)"])
			}
		}

		fileprivate let encoder = JSONEncoder()

		let env:QuickLMDB.Environment

		private let kindDB:KindDatabase
		
		// stores a given event ID and the JSON-encoded event.
		let eventDB_core:Database 	// [Data:nostr.Event]

		init(env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
			self.env = env
			let subTrans = try Transaction(env, readOnly:false, parent: someTrans)
			self.eventDB_core = try env.openDatabase(named:Databases.events_core.rawValue, flags:[.create], tx:subTrans)
			self.kindDB = try KindDatabase(env, tx:subTrans)
			try subTrans.commit()
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
			let kindFilter:KindDatabase.KindFilter
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
	}
}
