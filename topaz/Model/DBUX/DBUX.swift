import QuickLMDB
import class Foundation.JSONDecoder
import struct Foundation.TimeInterval
import struct Foundation.UUID
import struct Foundation.Data
import Darwin
import Logging
import class Foundation.FileManager
import struct Foundation.URL
import SwiftBlake2

// encompasses the user experience 
public class DBUX:Based {
	let dispatcher:Dispatcher<DBUX.Notification>
	
	let logger:Logger
	let base:URL
	
	let keypair:nostr.KeyPair
	
	let contactsEngine:ContactsEngine

	let profilesEngine:ProfilesEngine

	let contextEngine:ContextEngine

	let eventsEngine:EventsEngine

	let relaysEngine:RelaysEngine

	init(base:URL, keypair:nostr.KeyPair) throws {
		self.dispatcher = Dispatcher<Notification>(logLabel:"dbux-\(keypair.pubkey.description)", logLevel:.info)
		let makeLogger = Topaz.makeDefaultLogger(label:"dbux")
		self.keypair = keypair
		self.logger = makeLogger
		let makeBase = base.appendingPathComponent("uid-\(keypair.pubkey.description)", isDirectory:true)
		if FileManager.default.fileExists(atPath: makeBase.path) == false {
			try FileManager.default.createDirectory(atPath:makeBase.path, withIntermediateDirectories:true)
		}
		
		self.contactsEngine = try! Topaz.launchExperienceEngine(ContactsEngine.self, from:makeBase, for:keypair.pubkey, dispatcher:dispatcher)
		self.profilesEngine = try! Topaz.launchExperienceEngine(ProfilesEngine.self, from:makeBase, for:keypair.pubkey, dispatcher:dispatcher)
		self.contextEngine = try! Topaz.launchExperienceEngine(ContextEngine.self, from:makeBase, for:keypair.pubkey, dispatcher:dispatcher)
		self.eventsEngine = try! EventsEngine(base:makeBase, pubkey:keypair.pubkey, dispatcher:dispatcher)
		self.relaysEngine = try! Topaz.launchExperienceEngine(RelaysEngine.self, from:makeBase, for:keypair.pubkey, dispatcher:dispatcher)
		self.base = makeBase
		
		let myRelays:Set<String>
		do {
			myRelays = try self.relaysEngine.getRelays(pubkey:keypair.pubkey.description)
		} catch LMDBError.notFound {
			myRelays = Set(Topaz.defaultRelays.compactMap { $0.url })
		}
		let homeSubs = try! self.buildMainUserFilters()
		for curRelay in myRelays {
			try relaysEngine.add(subscriptions:[nostr.Subscribe(sub_id:UUID().uuidString, filters:homeSubs)], to:curRelay)
		}
		
		Task.detached { [weak self, hol = self.relaysEngine.holder] in
			guard let self = self else {
				return
			}
			let decoder = JSONDecoder()
			for try await curEvs in hol {
				var buildProfiles = [nostr.Key:nostr.Profile]()
				var profileUpdateDates = [nostr.Key:DBUX.Date]()
				for curEv in curEvs {
					switch curEv.kind {
					case .metadata:
						do {
							let asData = Data(curEv.content.utf8)
							let decoded = try decoder.decode(nostr.Profile.self, from:asData)
							self.logger.info("successfully decoded profile", metadata:["pubkey":"\(curEv.pubkey)"])
							buildProfiles[curEv.pubkey] = decoded
							profileUpdateDates[curEv.pubkey] = curEv.created
						} catch {
							self.logger.error("failed to decode profile.")
						}
					case .contacts:
						do {
							let asData = Data(curEv.content.utf8)
							let relays = Set(try decoder.decode([String:[String:Bool]].self, from:asData).keys)
							var following = Set<nostr.Key>()
							for curTag in curEv.tags {
								if case curTag.kind = nostr.Event.Tag.Kind.pubkey, let getPubKey = curTag.info.first, let asKey = nostr.Key(getPubKey) {
									following.update(with:asKey)
								}
							}
							try self.relaysEngine.setRelays(relays, pubkey:curEv.pubkey, asOf:curEv.created)
							let followsTx = try self.contactsEngine.followsEngine.transact(readOnly:false)
							try self.contactsEngine.followsEngine.set(pubkey:curEv.pubkey, follows:following, tx:followsTx)
							if curEv.pubkey == self.keypair.pubkey {
								// write the new home subscription
								var homeFilter = nostr.Filter()
								homeFilter.kinds = [.text_note, .like, .boost]
								homeFilter.authors = Array(following.compactMap({ $0.description }))
								
							}
							try followsTx.commit()
							self.logger.info("updated contact information.", metadata:["pubkey":"\(curEv.pubkey)"])
						} catch let error {}
						
					default:
						self.logger.debug("got event.", metadata:["kind":"\(curEv.kind)"])
					}
				}
				
				await withThrowingTaskGroup(of:Void.self, body: { [pe = self.profilesEngine, newEvsSet = Set(curEvs), tle = self.eventsEngine.timelineEngine, bp = buildProfiles] tg in
					
//					 write the events to the timeline
					tg.addTask { [newEvsSet, tle] in
						let tltx = try tle.transact(readOnly:false)
						try tle.writeEvents(newEvsSet, tx:tltx)
						try tltx.commit()
					}
					
					// write the new profiles to the database
					tg.addTask { [pe, bp] in
						let pftx = try pe.transact(readOnly:false)
						try pe.setPublicKeys(bp, tx:pftx)
						try pftx.commit()
					}
				})
			}
		}
		Task.detached {
			await self.dispatcher.addListener(forEventType:.currentUserFollowsUpdated, { _ in
				print("DOING IT")
			})
		}
		
	}
//	
	func getHomeTimelineState() throws -> ([nostr.Event], [nostr.Key:nostr.Profile]) {
		let contextOpen = try contextEngine.getTimelineAnchor()
		let tltx = try eventsEngine.timelineEngine.transact(readOnly:true)
		let events = try eventsEngine.timelineEngine.readEvents(from:contextOpen, tx:tltx, filter: { nostrID in
			return true
		})
		try tltx.commit()
		let profilesTx = try profilesEngine.transact(readOnly:true)
		let profiles = try self.profilesEngine.getPublicKeys(publicKeys:Set(events.compactMap({ $0.pubkey })), tx: profilesTx)
		try profilesTx.commit()
		return (events.sorted(by: { $0.created < $1.created }), profiles)
	}

	func buildMainUserFilters() throws -> [nostr.Filter] {
		let newTransaction = try self.contactsEngine.followsEngine.transact(readOnly:true)
		// get the friends list
		let myFriends = try self.contactsEngine.followsEngine.getFollows(pubkey:self.keypair.pubkey, tx:newTransaction)
		try newTransaction.commit()
		
		let friendString = myFriends.compactMap({ $0.description })
		
		// build the contacts filter
		var contactsFilter = nostr.Filter()
		contactsFilter.authors = Array(friendString)
		contactsFilter.kinds = [.metadata]

		
		// build "blocklist" filter
		var blocklistFilter = nostr.Filter()
		blocklistFilter.kinds = [.list_categorized]
		blocklistFilter.parameter = ["mute"]
		blocklistFilter.authors = [self.keypair.pubkey.description]

		// build "dms" filter
		var dmsFilter = nostr.Filter()
		dmsFilter.kinds = [.dm]
		dmsFilter.authors = [self.keypair.pubkey.description]

		// build "our" dms filter
		var ourDMsFilter = nostr.Filter()
		ourDMsFilter.kinds = [.dm]
		ourDMsFilter.authors = [self.keypair.pubkey.description]

		// create home filter
		var homeFilter = nostr.Filter()
		homeFilter.kinds = [.text_note, .like, .boost]
		homeFilter.authors = Array(friendString)

		// // create "notifications" filter
		// var notificationsFilter = nostr.Filter()
		// notificationsFilter.kinds = [.like, .boost, .text_note, .zap]
		// notificationsFilter.limit = 500

		// return [contactsFilter]
		return [contactsFilter, blocklistFilter, dmsFilter, ourDMsFilter, homeFilter]
	}
}

extension DBUX {
	// since QuickLMDB implements a default encoding scheme for Foundation.Date that does not work for our needs here, we implement our own type and encoding scheme for Date.
	// the primary primitive for the Date type is a TimeInterval, which is the number of seconds since the Swift date "Reference Date" (Jan 1, 2001, 00:00:00 GMT)
	@frozen @usableFromInline internal struct Date:MDB_convertible, MDB_comparable, Hashable, Equatable, Comparable {
		/// the primitive value of this instance
		let rawVal:TimeInterval

		/// basic initializer based on the primitive
		init(referenceInterval:TimeInterval) {
			self.rawVal = referenceInterval
		}

		/// initialize from database
		@usableFromInline init?(_ value:MDB_val) {
			guard MemoryLayout<Self>.size == value.mv_size else {
				return nil
			}
			self = value.mv_data.bindMemory(to:Self.self, capacity:1).pointee
		}

		/// encode into database
		@usableFromInline internal func asMDB_val<R>(_ valFunc:(inout MDB_val) throws -> R) rethrows -> R {
			return try withUnsafePointer(to:self, { unsafePointer in
				var val = MDB_val(mv_size:MemoryLayout<Self>.size, mv_data:UnsafeMutableRawPointer(mutating:unsafePointer))
				return try valFunc(&val)
			})
		}

		/// returns the difference in time between the called instance and passed date
		@usableFromInline internal func timeIntervalSince(_ other:Self) -> TimeInterval {
			return self.rawVal - other.rawVal
		}

		/// returns a new value that is the sum of the current value and the passed interval
		@usableFromInline internal func addingTimeInterval(_ interval:TimeInterval) -> Self {
			return Self(referenceInterval:self.rawVal + interval)
		}

		/// custom LMDB comparison function for the encoding scheme of this type
		@usableFromInline internal static let mdbCompareFunction:@convention(c) (UnsafePointer<MDB_val>?, UnsafePointer<MDB_val>?) -> Int32 = { a, b in
			let aTI = a!.pointee.mv_data!.assumingMemoryBound(to: Self.self).pointee
			let bTI = b!.pointee.mv_data!.assumingMemoryBound(to: Self.self).pointee
			if aTI.rawVal < bTI.rawVal {
				return -1
			} else if aTI.rawVal > bTI.rawVal {
				return 1
			} else {
				return 0
			}
		}

		/// hashable conformance
		public func hash(into hasher:inout Hasher) {
			hasher.combine(rawVal)
		}

		/// comparable conformance
		static public func < (lhs:Self, rhs:Self) -> Bool {
			return lhs.asMDB_val({ lhsVal in
				rhs.asMDB_val({ rhsVal in
					Self.mdbCompareFunction(&lhsVal, &rhsVal) < 0
				})
			})
		}

		/// equatable conformance
		static public func == (lhs:Self, rhs:Self) -> Bool {
			return lhs.rawVal == rhs.rawVal
		}
	}
}

extension DBUX {
	@frozen @usableFromInline internal struct DatedNostrEventUID:MDB_convertible, MDB_comparable, Hashable, Equatable, Comparable {
		let date:DBUX.Date
		@usableFromInline let uid:nostr.Event.UID

		internal static func dateFromMDBVal(value: MDB_val) -> Date? {
			if value.mv_data == nil || value.mv_size < MemoryLayout<Date>.size {
				return nil
			}
			let timeIntervalVal = MDB_val(mv_size: MemoryLayout<Date>.size, mv_data: UnsafeMutableRawPointer(value.mv_data!))
			return Date(timeIntervalVal)
		}

		internal static func uidFromMDBVal(value: MDB_val) -> nostr.Event.UID? {
			if value.mv_data == nil || value.mv_size < MemoryLayout<Date>.size {
				return nil
			}
			let bytes = value.mv_data!.advanced(by: MemoryLayout<Date>.size).assumingMemoryBound(to: UInt8.self)
			let objSize = value.mv_size - MemoryLayout<Date>.size
			let objDataVal = MDB_val(mv_size: objSize, mv_data: bytes)
			return nostr.Event.UID(objDataVal)
		}

		internal init(event:nostr.Event) {
			self.date = event.created
			self.uid = event.uid
		}

		internal init(date: Date, obj:nostr.Event.UID) {
			self.date = date
			self.uid = obj
		}

		@usableFromInline internal init?(_ value: MDB_val) {
			let totalSize = value.mv_size
			guard totalSize > MemoryLayout<Date>.size else {
				return nil
			}
			guard let date = Self.dateFromMDBVal(value: value) else {
				return nil
			}
			guard let obj = Self.uidFromMDBVal(value: value) else {
				return nil
			}
			self.date = date
			self.uid = obj
		}

		public func asMDB_val<R>(_ valFunc: (inout MDB_val) throws -> R) rethrows -> R {
			try withUnsafePointer(to:self, { unsafePointer in
				var val = MDB_val(mv_size:MemoryLayout<Self>.size, mv_data:UnsafeMutableRawPointer(mutating:unsafePointer))
				return try valFunc(&val)
			})
		}

		public static let mdbCompareFunction: MDB_comparable.MDB_compare_function = { a, b in
			let dateComparisonResult = Date.mdbCompareFunction(a, b)
			if dateComparisonResult != 0 {
				return dateComparisonResult
			} else {
				return Self.uidFromMDBVal(value: a!.pointee)!.asMDB_val({ aObjVal in
					return Self.uidFromMDBVal(value: b!.pointee)!.asMDB_val({ bObjVal in
						return nostr.Event.UID.mdbCompareFunction(&aObjVal, &bObjVal)
					})
				})
			}
		}

		public static let invertedDateMDBCompareFunction:MDB_compare_function = { a, b in
			let dateComparisonResult = Date.mdbCompareFunction(a, b)
			if dateComparisonResult != 0 {
				return -dateComparisonResult
			} else {
				return Self.uidFromMDBVal(value: a!.pointee)!.asMDB_val({ aObjVal in
					return Self.uidFromMDBVal(value: b!.pointee)!.asMDB_val({ bObjVal in
						return nostr.Event.UID.mdbCompareFunction(&aObjVal, &bObjVal)
					})
				})
			}
		}

		@usableFromInline static func invertedDateCompare(_ lhs: Self, _ rhs: Self) -> Bool {
			return lhs.asMDB_val({ lhsVal in
				rhs.asMDB_val({ rhsVal in
					return Self.invertedDateMDBCompareFunction(&lhsVal, &rhsVal) < 0
				})
			})
		}

		@usableFromInline static func < (lhs: Self, rhs: Self) -> Bool {
			return lhs.asMDB_val({ lhsVal in
				rhs.asMDB_val({ rhsVal in
					Self.mdbCompareFunction(&lhsVal, &rhsVal) < 0
				})
			})
		}

		@usableFromInline static func == (lhs: Self, rhs: Self) -> Bool {
			return lhs.asMDB_val({ lhsVal in
				rhs.asMDB_val({ rhsVal in
					Self.mdbCompareFunction(&lhsVal, &rhsVal) == 0
				})
			})
		}

		public func hash(into hasher:inout Hasher) {
			date.asMDB_val({ dateVal in
				hasher.combine(bytes: UnsafeRawBufferPointer(start: dateVal.mv_data, count: dateVal.mv_size))
			})
			uid.asMDB_val({ objVal in
				hasher.combine(bytes: UnsafeRawBufferPointer(start: objVal.mv_data, count: objVal.mv_size))
			})
		}
	}
}

extension DBUX {
	struct RelayHash:MDB_convertible, MDB_comparable, Hashable, Equatable, Comparable {
		static func produceHash(from url:String) throws -> Data {
			var hasher = try Blake2bHasher(outputLength: 6)
			try Data(url.utf8).withUnsafeBytes { relayBytes in
				try hasher.update(relayBytes)
			}
			return try hasher.export()
		}
		
		// 6 byte tuple
		var bytes:(UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0)
		
		@usableFromInline init(rawHashData:Data) {
			guard rawHashData.count == MemoryLayout<Self>.size else {
				return
			}
			rawHashData.withUnsafeBytes({ byteBuffer in
				memcpy(&bytes, byteBuffer, MemoryLayout<Self>.size)
			})
		}
		@usableFromInline init(_ string:String) throws {
			self = .init(rawHashData:try Self.produceHash(from: string))
		}
		@usableFromInline init() {}
		@usableFromInline init(_ value: MDB_val) {
			let totalSize = value.mv_size
			guard totalSize == MemoryLayout<Self>.size else {
				return
			}
			let bytes = value.mv_data!.assumingMemoryBound(to: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8).self)
			self.bytes = bytes.pointee
		}
		@usableFromInline func asMDB_val<R>(_ valFunc: (inout MDB_val) throws -> R) rethrows -> R {
			try withUnsafePointer(to:self, { unsafePointer in
				var val = MDB_val(mv_size:MemoryLayout<Self>.size, mv_data:UnsafeMutableRawPointer(mutating:unsafePointer))
				return try valFunc(&val)
			})
		}

		@usableFromInline static func < (lhs: Self, rhs: Self) -> Bool {
			return lhs.asMDB_val({ lhsVal in
				rhs.asMDB_val({ rhsVal in
					Self.mdbCompareFunction(&lhsVal, &rhsVal) < 0
				})
			})
		}

		@usableFromInline static func == (lhs: Self, rhs: Self) -> Bool {
			return lhs.asMDB_val({ lhsVal in
				rhs.asMDB_val({ rhsVal in
					Self.mdbCompareFunction(&lhsVal, &rhsVal) == 0
				})
			})
		}

		public func hash(into hasher:inout Hasher) {
			self.asMDB_val({ selfVal in
				hasher.combine(bytes: UnsafeRawBufferPointer(start: &selfVal, count:MemoryLayout<Self>.size))
			})
			
		}

		@usableFromInline static let mdbCompareFunction:@convention(c) (UnsafePointer<MDB_val>?, UnsafePointer<MDB_val>?) -> Int32 = { a, b in
			let aData = a!.pointee.mv_data!.assumingMemoryBound(to: Self.self)
			let bData = b!.pointee.mv_data!.assumingMemoryBound(to: Self.self)
			
			let minLength = min(a!.pointee.mv_size, b!.pointee.mv_size)
			let comparisonResult = memcmp(aData, bData, minLength)

			if comparisonResult != 0 {
				return Int32(comparisonResult)
			} else {
				// If the common prefix is the same, compare their lengths.
				return Int32(a!.pointee.mv_size) - Int32(b!.pointee.mv_size)
			}
		}
	}
}
