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


extension DBUX.EventsEngine.KindsEngine {
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
}

extension DBUX.EventsEngine {
	struct KindsEngine:SharedExperienceEngine {
		typealias NotificationType = DBUX.Notification
		
		static let name = "event-engine-kind-id.mdb"
		static let deltaSize = size_t(5.12e+8)
		static let maxDBs:MDB_dbi = 2
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let dispatcher: Dispatcher<DBUX.Notification>

		let env:QuickLMDB.Environment
		let pubkey:nostr.Key
		
		enum Databases:String {
			case kind_uid = "kind-uid"
			case uid_kind = "uid-kind"
		}

		let logger:Logger

		// stores the given UIDs that are associated with the given kind
		let kind_uid:Database
		// stores the kind associated with the given UID
		let uid_kind:Database

		init(env:QuickLMDB.Environment, keyPair:nostr.KeyPair, dispatcher:Dispatcher<NotificationType>) throws {
			self.dispatcher = dispatcher
			self.env = env
			self.pubkey = keyPair.pubkey
			self.logger = try Topaz.makeDefaultLogger(label:"event-engine-kind-id.mdb")
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
					try uidKCursor.setEntry(value:event.kind, forKey:event.uid, flags:[.noOverwrite])
				} catch LMDBError.keyExists {}
				try kUIDCursor.setEntry(value:event.uid, forKey:event.kind)
			}
			try subTrans.commit()
			self.logger.debug("successfully installed events.", metadata:["count": "\(events.count)"])
		}

		/// get all kinds for a given uid
		/// - never throws LMDBError.notFound
		func getKinds(uids:Set<nostr.Event.UID>, tx someTrans:QuickLMDB.Transaction) throws -> [nostr.Event.UID:nostr.Event.Kind] {
			let uidKCursor = try self.uid_kind.cursor(tx:someTrans)
			var ret = [nostr.Event.UID:nostr.Event.Kind]()
			for uid in uids {
				ret[uid] = nostr.Event.Kind(try uidKCursor.getEntry(.set, key:uid).value)!
			}
			return ret
		}

		/// removes the given uids from the database
		func deleteEvents(uids:Set<nostr.Event.UID>, tx someTrans:QuickLMDB.Transaction) throws {
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
			self.logger.debug("successfully deleted events.", metadata:["count": "\(uids.count)"])
		}

		func getKindFilter(kind:nostr.Event.Kind, tx someTrans:QuickLMDB.Transaction) throws -> Filter {
			return try Filter(self.kind_uid, kind:kind, tx:someTrans)
		}
	}
}

extension DBUX {
	struct DatesEngine:SharedExperienceEngine {
		typealias NotificationType = DBUX.Notification
		
		static let name = "event-engine-date-id.mdb"
		static let maxDBs:MDB_dbi = 2
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let dispatcher: Dispatcher<DBUX.Notification>
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

		init(env:QuickLMDB.Environment, keyPair:nostr.KeyPair, dispatcher:Dispatcher<NotificationType>) throws {
			self.dispatcher = dispatcher
			self.env = env
			self.pubkey = keyPair.pubkey
			self.logger = Topaz.makeDefaultLogger(label:"event-engine-date-id.mdb")
			let someTrans = try Transaction(env, readOnly:false)
			self.date_uid = try env.openDatabase(named:Databases.date_uid.rawValue, flags:[.create, .dupSort], tx:someTrans)
			self.uid_date = try env.openDatabase(named:Databases.uid_date.rawValue, flags:[.create, .dupSort], tx:someTrans)
			try someTrans.commit()
		}

		func set(events:Set<nostr.Event>, tx someTrans:QuickLMDB.Transaction) throws {
			let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
			let dateUCursor = try self.date_uid.cursor(tx:subTrans)
			let uidDCursor = try self.uid_date.cursor(tx:subTrans)
			for event in events {
				try dateUCursor.setEntry(value:event.uid, forKey:event.created)
				try uidDCursor.setEntry(value:event.created, forKey:event.uid)
			}
			try subTrans.commit()
		}
	}
}

extension DBUX {
	struct PublishersEngine:SharedExperienceEngine {
		typealias NotificationType = DBUX.Notification
		static let maxDBs: MDB_dbi = 2
		static let env_flags: QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let dispatcher: Dispatcher<NotificationType>
		let env: QuickLMDB.Environment
		let pubkey: nostr.Key
		let logger: Logger
		enum Databases: String {
			case key_uid = "key-uid"
			case uid_key = "uid-key"
		}

		// stores the given UIDs that are associated with the given key
		let key_uid: Database // [nostr.Key: nostr.Event.UID]
		// stores the key associated with the given UID
		let uid_key: Database // [nostr.Event.UID: nostr.Key]

		init(env: QuickLMDB.Environment, keyPair: nostr.KeyPair, dispatcher:Dispatcher<NotificationType>) throws {
			self.dispatcher = dispatcher
			self.env = env
			self.pubkey = keyPair.pubkey
			self.logger = Topaz.makeDefaultLogger(label: "event-engine-key-uid.mdb")
			let someTrans = try Transaction(env, readOnly: false)
			self.key_uid = try env.openDatabase(named: Databases.key_uid.rawValue, flags: [.create, .dupSort], tx: someTrans)
			self.uid_key = try env.openDatabase(named: Databases.uid_key.rawValue, flags: [.create, .dupSort], tx: someTrans)
			try someTrans.commit()
		}

		func set(events: Set<nostr.Event>, tx someTrans: QuickLMDB.Transaction) throws {
			let subTrans = try Transaction(env, readOnly: false, parent: someTrans)
			let keyUCursor = try self.key_uid.cursor(tx: subTrans)
			let uidKCursor = try self.uid_key.cursor(tx: subTrans)
			for event in events {
				try keyUCursor.setEntry(value: event.uid, forKey: event.pubkey)
				try uidKCursor.setEntry(value: event.pubkey, forKey: event.uid)
			}
			try subTrans.commit()
		}
	}
}


extension DBUX {
	struct EventsEngine:ExperienceEngine {
		typealias NotificationType = DBUX.Notification
		static let name = "events-engine.mdb"
		static let deltaSize = SizeMode.fixed(size_t(2.5e+9))
		static let maxDBs:MDB_dbi = 32
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let dispatcher: Dispatcher<DBUX.Notification>
		var base:URL
		let env:QuickLMDB.Environment
		let pubkey:nostr.Key

		let logger:Logger
//		let dateIDs:DatesEngine
//		let publishers:PublishersEngine
		let timelineEngine:TimelineEngine
		let followsEngine:FollowsEngine
		let relaysEngine:RelaysEngine
		let profilesEngine:ProfilesEngine
		
		init(base: URL, env: QuickLMDB.Environment, keyPair: nostr.KeyPair, dispatcher: Dispatcher<DBUX.Notification>) throws {
			self.base = base
			self.dispatcher = dispatcher
//			self.dateIDs = try Topaz.launchSharedExperienceEngine(DatesEngine.self, base:base, env:env, for:publicKey, dispatcher: dispatcher)
//			self.publishers = try Topaz.launchSharedExperienceEngine(PublishersEngine.self, base:base, env:env, for:publicKey, dispatcher: dispatcher)
			self.timelineEngine = try Topaz.launchExperienceEngine(TimelineEngine.self, from:base.deletingLastPathComponent(), for:keyPair, dispatcher: dispatcher)
			self.followsEngine = try Topaz.launchSharedExperienceEngine(FollowsEngine.self, base: base, env:env, for:keyPair, dispatcher: dispatcher)
			self.relaysEngine = try Topaz.launchSharedExperienceEngine(RelaysEngine.self, base:base, env:env, for:keyPair, dispatcher:dispatcher)
			self.profilesEngine = try Topaz.launchSharedExperienceEngine(ProfilesEngine.self, base:base, env: env, for: keyPair, dispatcher: dispatcher)
			self.env = env
			self.pubkey = keyPair.pubkey
			self.base = base
			self.logger = Topaz.makeDefaultLogger(label: "events-engine")
		}
	}
}

extension DBUX.EventsEngine {
	class TimelineEngine:ExperienceEngine {
		static let name: String = "timeline-engine.mdb"
		typealias NotificationType = DBUX.Notification
		static let deltaSize = SizeMode.fixed(size_t(2.5e+8))
		static let maxDBs: MDB_dbi = 1
		static let env_flags: QuickLMDB.Environment.Flags = [.noSubDir, .noReadAhead, .noSync]
		let dispatcher:Dispatcher<NotificationType>
		let env: QuickLMDB.Environment
		let pubkey: nostr.Key
		let logger: Logger
		let base: URL
		enum Databases: String {
			case timelineMain_DB = "timelineMain_DB"
		}
		
		let decoder = JSONDecoder()
		let encoder = JSONEncoder()
		
		let allDB: Database // database structure [DBUX.DatedNostrEventUID: nostr.Event]

		required init(base: URL, env: QuickLMDB.Environment, keyPair: nostr.KeyPair, dispatcher: Dispatcher<DBUX.Notification>) throws {
			self.dispatcher = dispatcher
			self.env = env
			self.base = base
			self.pubkey = keyPair.pubkey
			self.logger = Topaz.makeDefaultLogger(label: "timeline-engine.mdb")
			let someTrans = try Transaction(env, readOnly: false)
			self.allDB = try env.openDatabase(named:Databases.timelineMain_DB.rawValue, flags:[.create], tx: someTrans)
			try self.allDB.setCompare(tx:someTrans, DBUX.DatedNostrEventUID.mdbCompareFunction)
			let getEventsCount = try self.allDB.getStatistics(tx:someTrans).entries
			try someTrans.commit()
		}

		@discardableResult
		func writeEvents(_ events: Set<nostr.Event>, target:DBUX.DatedNostrEventUID, catchMemory:Bool = true) throws -> Set<DBUX.DatedNostrEventUID> {
			let eventsByDateID = Dictionary(grouping: events, by: { DBUX.DatedNostrEventUID(event:$0) }).compactMapValues({ $0.first })
			let sortedDateIDs = eventsByDateID.keys.sorted(by: { $0 < $1 })
			var returnValues = Set<DBUX.DatedNostrEventUID>()
			let mainTrans = try Transaction(env, readOnly: false)
			func writeEvents() throws {
				let subTrans = try Transaction(env, readOnly:false, parent:mainTrans)
				let allDBCursor = try self.allDB.cursor(tx: subTrans)
				for curDate in sortedDateIDs {
					let encoded = try encoder.encode(eventsByDateID[curDate]!)
					try allDBCursor.setEntry(value:encoded, forKey:curDate)
					returnValues.update(with:curDate)
				}
				try subTrans.commit()
			}
			do {
				try writeEvents()
			} catch LMDBError.mapFull {
				if catchMemory == true {
					let subTrans = try Transaction(env, readOnly:false, parent:mainTrans)
					try self.reduceEventsCount(target: target, tx:subTrans)
					try subTrans.commit()
					try writeEvents()
				} else {
					throw LMDBError.mapFull
				}
			}
			try mainTrans.commit()
			return returnValues
		}

		func readEvents(_ ids: Set<DBUX.DatedNostrEventUID>) throws -> [DBUX.DatedNostrEventUID:Result<nostr.Event, Swift.Error>] {
			var returnValues = [DBUX.DatedNostrEventUID:Result<nostr.Event, Swift.Error>]()
			let someTrans = try Transaction(env, readOnly:true)
			let allDBCursor = try self.allDB.cursor(tx: someTrans)
			for curID in ids.sorted(by: { $0 < $1 }) {
				do {
					let curEvent = Data(try allDBCursor.getEntry(.set, key:curID).value)!
					returnValues[curID] = .success(try decoder.decode(nostr.Event.self, from:curEvent))
				} catch let error {
					returnValues[curID] = .failure(error)
				}
			}
			try someTrans.commit()
			return returnValues
		}
		
		@discardableResult func deleteEvents(_ ids:Set<DBUX.DatedNostrEventUID>) throws -> [DBUX.DatedNostrEventUID:Result<nostr.Event, Swift.Error>] {
			let someTrans = try Transaction(env, readOnly:true)
			var returnValues = [DBUX.DatedNostrEventUID:Result<nostr.Event, Swift.Error>]()
			let allDBCursor = try self.allDB.cursor(tx: someTrans)
			for curID in ids.sorted(by: { $0 < $1 }) {
				do {
					let curEvent = Data(try allDBCursor.getEntry(.set, key:curID).value)!
					returnValues[curID] = .success(try decoder.decode(nostr.Event.self, from:curEvent))
					try allDBCursor.deleteEntry()
				} catch let error {
					returnValues[curID] = .failure(error)
				}
			}
			try someTrans.commit()
			return returnValues
		}
		
		enum ReadDirection {
			case forward
			case backward
		}
		func readEvents(from marker: DBUX.DatedNostrEventUID?, limit: UInt16 = 48, direction: UI.TimelineViewModel.ScrollDirection, usersOut:inout Set<nostr.Key>, filter shouldInclude: (nostr.Event.UID) throws -> Bool) throws -> [nostr.Event] {
			let someTrans = try Transaction(env, readOnly:true)
			let allDBCursor = try self.allDB.cursor(tx: someTrans)
			var returnValues: [nostr.Event] = []
			var currentEntry: (key: MDB_val, value: MDB_val)
			
			if let hasMarker = marker {
				do {
					currentEntry = try allDBCursor.getEntry(.set, key: hasMarker)
				} catch LMDBError.notFound {
					do {
						currentEntry = try allDBCursor.getEntry(.setRange, key: hasMarker)
					} catch LMDBError.notFound {
						currentEntry = try allDBCursor.getEntry(.last)
					}
				}
			} else {
				currentEntry = try allDBCursor.getEntry(.last)
			}
			
			do {
				repeat {
					let getUID = DBUX.DatedNostrEventUID(currentEntry.key)!.uid
					if try shouldInclude(getUID) == true {
						let parsed = try! decoder.decode(nostr.Event.self, from: Data(currentEntry.value)!)
						returnValues.append(parsed)
						usersOut.update(with:parsed.pubkey)
					}
					
					switch direction {
					case .up:
						currentEntry = try allDBCursor.getEntry(.next)
					case .down:
						currentEntry = try allDBCursor.getEntry(.previous)
					}
				} while returnValues.count < limit
			} catch LMDBError.notFound {
			}
			try someTrans.commit()
			return returnValues
		}
		
		// Reduces the total count of events by a given factor, with a preference for deleting events furthest away from the specified target DBUX.DatedNostrEventUID and the last point
		func reduceEventsCount(by reductionFactor: Double = 0.35, target: DBUX.DatedNostrEventUID, tx someTrans: QuickLMDB.Transaction) throws {
			let subTrans = try Transaction(env, readOnly: false, parent: someTrans)
			let allDBCursor = try self.allDB.cursor(tx: subTrans)

			var events = [DBUX.DatedNostrEventUID]()

			do {
				var curEntry = try allDBCursor.getEntry(.first)
				repeat {
					let eventID = DBUX.DatedNostrEventUID(curEntry.key)!
					events.append(eventID)
					curEntry = try allDBCursor.getEntry(.next)
				} while true
			} catch LMDBError.notFound {}

			let reducedCount = Int(Double(events.count) * (1 - reductionFactor))
			let lastEventTimestamp = events.last!.date
			let sortedEvents = events.sorted {
				let distanceA = abs($0.date.timeIntervalSince(target.date)) + abs($0.date.timeIntervalSince(lastEventTimestamp))
				let distanceB = abs($1.date.timeIntervalSince(target.date)) + abs($1.date.timeIntervalSince(lastEventTimestamp))
				return distanceA < distanceB
			}
			let eventsToKeep = Array(sortedEvents.prefix(reducedCount))

			let eventsToRemove = Set(events).subtracting(eventsToKeep)

			for eventID in eventsToRemove {
				try allDBCursor.getEntry(.set, key:eventID)
				try allDBCursor.deleteEntry()
			}

			try subTrans.commit()
			self.logger.debug("Successfully reduced events count by \(reductionFactor * 100)% with a preference for deleting events furthest away from the target and the last point.", metadata: ["target": "\(target)"])
		}
	}

}
