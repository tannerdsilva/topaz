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

			let env:QuickLMDB.Environment

			// * does not allow an override of an existing entry if the values are not the same *
			let uid_kind:Database		// [UID:String]
			let kind_uid:Database		// [Kind:String] * DUP *

			init(_ env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
				self.env = env
				self.uid_kind = try env.openDatabase(named:Databases.uid_kind.rawValue, flags:[.create], tx:someTrans)
				self.kind_uid = try env.openDatabase(named:Databases.kind_uid.rawValue, flags:[.create], tx:someTrans)
			}

			/// bulk import events into the database
			/// - for each public key, the event kinds will attempt to be assigned
			/// - will NOT overwrite existing data if the specified public key is already in the database
			/// - will NOT throw ``LMDBError.keyExists`` if the public key is already in the database with the same kind
			func setEvent(_ events:Set<nostr.Event>, tx someTrans:QuickLMDB.Transaction? = nil) throws {
				let subTrans = try Transaction(env, readOnly:false, parent: someTrans)
				let uidKCursor = try self.uid_kind.cursor(tx:subTrans)
				let kUIDCursor = try self.kind_uid.cursor(tx:subTrans)
				for event in events {
					do {
						try uidKCursor.setEntry(value:event.kind, forKey:event.uid, flags:[.noOverwrite])
					} catch {
						// throw an error if the key already exists and the value is not the same
						guard nostr.Event.Kind(rawValue:Int(try uidKCursor.getEntry(.set, key:event.uid).value)!) == event.kind else {
							throw LMDBError.keyExists
						}
					}
					try kUIDCursor.setEntry(value:event.uid, forKey:event.kind)
				}
				try subTrans.commit()
				Self.logger.debug("successfully installed events.", metadata:["count": "\(events.count)"])
			}

			/// get all kinds for a given uid
			/// - never throws LMDBError.notFound
			func getKinds(uids:Set<String>, tx someTrans:QuickLMDB.Transaction? = nil) throws -> [String:nostr.Event.Kind] {
				let subTrans = try Transaction(env, readOnly:true, parent: someTrans)
				let uidKCursor = try self.uid_kind.cursor(tx:subTrans)
				var ret = [String:nostr.Event.Kind]()
				for uid in uids {
					ret[uid] = nostr.Event.Kind(rawValue:Int(try uidKCursor.getEntry(.set, key:uid).value)!)
				}
				try subTrans.commit()
				return ret
			}

			/// removes the given uids from the database
			func deleteEvents(uids:Set<String>, tx someTrans:QuickLMDB.Transaction? = nil) throws {
				let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
				let uidKCursor = try self.uid_kind.cursor(tx:subTrans)
				let kindUIDCursor = try self.kind_uid.cursor(tx:subTrans)
				for curID in uids {
					let getKind = try uidKCursor.getEntry(.set, key:curID).value
					let asKind = nostr.Event.Kind(getKind)!
					try kindUIDCursor.getEntry(.getBoth, key:asKind, value:curID)
					try kindUIDCursor.deleteEntry()
					try uidKCursor.deleteEntry()
				}
				try subTrans.commit()
				Self.logger.debug("successfully deleted events.", metadata:["count": "\(uids.count)"])
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
				try eventCursor.setEntry(value:encodedData, forKey:curEvent.uid)
			}
			try subTrans.commit()
		}

		func getEvents(limit:UInt64 = 50, tx someTrans:QuickLMDB.Transaction) throws -> [nostr.Event] {
			let subTrans = try Transaction(env, readOnly:true, parent:someTrans)
			let cursor = try self.eventDB_core.cursor(tx:subTrans)
			var buildEvents = [nostr.Event]()
			for (_, curEvent) in cursor {
				buildEvents.append(try JSONDecoder().decode(nostr.Event.self, from:Data(curEvent)!))
				if buildEvents.count > limit {
					try subTrans.commit()
					return buildEvents
				}
			}
			try subTrans.commit()
			return buildEvents
		}

		
	}
}
