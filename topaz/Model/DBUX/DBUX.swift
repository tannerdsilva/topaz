import QuickLMDB
import class Foundation.JSONEncoder
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
	enum Error:Swift.Error {
		case unableToEncrypt
	}
	let application:ApplicationModel
	let appDispatcher:Dispatcher<Topaz.Notification>
	let dispatcher:Dispatcher<DBUX.Notification>
	
	let logger:Logger
	let base:URL
	
	let keypair:nostr.KeyPair

	let contextEngine:ContextEngine

	let eventsEngine:EventsEngine
	
	let imageCache:ImageCache
	
	var mainTask:Task<Void, Never>? = nil

	init(app:ApplicationModel, base:URL, keypair:nostr.KeyPair, appDispatcher:Dispatcher<Topaz.Notification>) throws {
		self.application = app
		self.appDispatcher = appDispatcher
		self.dispatcher = Dispatcher<Notification>(logLabel:"dbux-\(keypair.pubkey.description)", logLevel:.info)
		let makeLogger = Topaz.makeDefaultLogger(label:"dbux")
		self.keypair = keypair
		self.logger = makeLogger
		let makeBase = base.appendingPathComponent("uid-\(keypair.pubkey.description)", isDirectory:true)
		if FileManager.default.fileExists(atPath: makeBase.path) == false {
			try FileManager.default.createDirectory(atPath:makeBase.path, withIntermediateDirectories:true)
		}
		
		self.contextEngine = try! Topaz.launchExperienceEngine(ContextEngine.self, from:makeBase, for:keypair.pubkey, dispatcher:dispatcher)
		self.eventsEngine = try! Topaz.launchExperienceEngine(EventsEngine.self, from:makeBase, for:keypair.pubkey, dispatcher:dispatcher)
		self.imageCache = try! Topaz.launchExperienceEngine(ImageCache.self, from:makeBase, for:keypair.pubkey, dispatcher:dispatcher)
		
		self.base = makeBase
		
		let relaysTX = try self.eventsEngine.transact(readOnly:false)
		let myRelays:Set<String>
		do {
			myRelays = try self.eventsEngine.relaysEngine.getRelays(pubkey:keypair.pubkey, tx:relaysTX)
		} catch LMDBError.notFound {
			myRelays = Set(Topaz.defaultRelays.compactMap { $0.url })
		}
		let myFollows:Set<nostr.Key>
		do {
			myFollows = try self.eventsEngine.followsEngine.getFollows(pubkey:keypair.pubkey, tx:relaysTX)
		} catch LMDBError.notFound {
			myFollows = Set<nostr.Key>()
		}
		let homeSubs = Self.generateMainSubscription(pubkey:self.keypair.pubkey, following:myFollows)
		for curRelay in myRelays {
			try self.eventsEngine.relaysEngine.add(subscriptions:[homeSubs], to:curRelay, tx:relaysTX)
		}
		try relaysTX.commit()

		mainTask = Task.detached { [weak self, hol = self.eventsEngine.relaysEngine.holder, disp = dispatcher, appDisp = appDispatcher, pubkey = self.keypair.pubkey] in
			await disp.addListener(forEventType:DBUX.Notification.applicationBecameFrontmost) { [weak self] _, _ in
				Task.detached { [weak self] in
					if let getItAll = await self?.eventsEngine.relaysEngine.getConnectionsAndStates() {
						let getDisconnected = getItAll.1.values.filter({ $0 == .disconnected })
						if getDisconnected.count > 0 {
							await withTaskGroup(of:Void.self) { tg in
								for curRelay in getItAll.0 {
									tg.addTask { [cr = curRelay] in
										try? await cr.value.connect()
									}
								}
							}
						}
					}
				}
			}

			await disp.addListener(forEventType:DBUX.Notification.currentUserProfileUpdated) { [appDisp = appDisp, pubkey = pubkey] _, newProf in
				guard let getProf = newProf as? nostr.Profile else {
					return
				}
				Task.detached { [appDisp = appDisp, newProf = getProf] in
					await appDisp.fireEvent(Topaz.Notification.userProfileInfoUpdated, associatedObject:Topaz.Account(key:pubkey, profile:newProf))
				}
			}
			try? await withTaskCancellationHandler(operation: {
				let decoder = JSONDecoder()
				for try await curEvs in hol {
					var profileDates = [nostr.Key:DBUX.Date]()
					var buildProfiles = [nostr.Key:nostr.Profile]()
					var profileUpdateDates = [nostr.Key:DBUX.Date]()

					var timelineEvents = Set<nostr.Event>()

					for (subID, curEv) in curEvs {
						guard let self = self else { return }
						switch curEv.kind {
						case .metadata:
							do {
								let asData = Data(curEv.content.utf8)
								let decoded = try decoder.decode(nostr.Profile.self, from:asData)
								self.logger.info("successfully decoded profile", metadata:["pubkey":"\(curEv.pubkey)"])
								profileDates[curEv.pubkey] = curEv.created
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
								let relaysTX = try self.eventsEngine.transact(readOnly:false)
								try self.eventsEngine.relaysEngine.setRelays(relays, pubkey:curEv.pubkey, asOf:curEv.created, tx:relaysTX)
								try self.eventsEngine.followsEngine.set(pubkey:curEv.pubkey, follows:following, tx:relaysTX)
								if curEv.pubkey == self.keypair.pubkey {
									let homeSubs = Self.generateMainSubscription(pubkey:self.keypair.pubkey, following:myFollows)
									for curRelay in myRelays {
										try self.eventsEngine.relaysEngine.add(subscriptions:[homeSubs], to:curRelay, tx:relaysTX)
									}
								}
								try relaysTX.commit()
								self.logger.info("updated contact information.", metadata:["pubkey":"\(curEv.pubkey)"])
							} catch let error {}

						case .text_note:
							timelineEvents.update(with:curEv)
							self.logger.debug("got event.", metadata:["kind":"\(curEv.kind)"])
						default: break
						}
					}

					if let hasEE = self?.eventsEngine {
						await withThrowingTaskGroup(of:Void.self, body: { [pe = hasEE.profilesEngine, newEvsSet = timelineEvents, tle = hasEE, bp = buildProfiles, pd = profileDates] tg in

		//					 write the events to the timeline
							tg.addTask { [newEvsSet, tle, pe, bp, pd] in
								let tltx = try tle.transact(readOnly:false)
								try tle.timelineEngine.writeEvents(newEvsSet, tx:tltx)
								try pe.setPublicKeys(bp, asOf:pd, tx:tltx)
								try tltx.commit()
							}

						})
					}
				}
			}, onCancel: {
				Task.detached(operation: { [hol] in
					await hol.finish()
				})
			})
		}
	}
	
	@MainActor func addFollow(_ key:nostr.Key) throws {
//		let relaysTX = try self.eventsEngine.transact(readOnly:true)
//		let getRelays = try self.eventsEngine.relaysEngine.getRelays(pubkey:self.keypair.pubkey, tx:relaysTX)
//		try relaysTX.commit()
//
//		try contactsTX.commit()
	}
	
	@MainActor func removeFollow(_ key:nostr.Key) throws {
//		let relaysTX = try self.eventsEngine.transact(readOnly:true)
//		let getRelays = try self.eventsEngine.relaysEngine.getRelays(pubkey: self.keypair.pubkey, tx:relaysTX)
//		try relaysTX.commit()
//		let contactsTX = try self.eventsEngine.followsEngine.transact(readOnly:false)
//		var getFollows = try self.followsEngine.getFollows(pubkey:self.keypair.pubkey, tx:contactsTX)
//		getFollows.remove(key)
//		try self.followsEngine.set(pubkey:self.keypair.pubkey, follows:getFollows, tx:contactsTX)
//		let newContactsEvent = try self.generateContactEvent(contacts:getFollows, relays: getRelays)
//		let getAllRelays = try self.relaysEngine.userRelayConnections
//		Task.detached { [conns = getAllRelays] in
//
//		}
	}
	
	@MainActor func addRelay(_ relay:String) throws {
		let openTx = try self.eventsEngine.transact(readOnly:false)
		let myFollows = try self.eventsEngine.followsEngine.getFollows(pubkey:self.keypair.pubkey, tx:openTx)
		var getRelays = try self.eventsEngine.relaysEngine.getRelays(pubkey:self.keypair.pubkey, tx:openTx)
		getRelays.update(with:relay)
		try self.eventsEngine.relaysEngine.setRelays(getRelays, pubkey:self.keypair.pubkey, asOf:DBUX.Date(), tx:openTx)
		let newEvent = try self.generateContactEvent(contacts:myFollows, relays:getRelays)
		try self.eventsEngine.relaysEngine.write(event:newEvent, to:getRelays, tx:openTx)
		try openTx.commit()
	}
	
	@MainActor func removeRelay(_ relay:String) throws {
		let openTx = try self.eventsEngine.transact(readOnly:false)
		let myFollows = try self.eventsEngine.followsEngine.getFollows(pubkey:self.keypair.pubkey, tx:openTx)
		var getRelays = try self.eventsEngine.relaysEngine.getRelays(pubkey:self.keypair.pubkey, tx:openTx)
		getRelays.remove(relay)
		try self.eventsEngine.relaysEngine.setRelays(getRelays, pubkey:self.keypair.pubkey, asOf:DBUX.Date(), tx:openTx)
		let newEvent = try self.generateContactEvent(contacts:myFollows, relays:getRelays)
		try self.eventsEngine.relaysEngine.write(event:newEvent, to:getRelays, tx:openTx)
		try openTx.commit()
	}
	
	@MainActor func updateProfile(_ newCurrentUserProfileInfo:nostr.Profile) throws {
		let newDAte = DBUX.Date()
		let encodedProfile = try JSONEncoder().encode(newCurrentUserProfileInfo)
		let encodedString = String(data:encodedProfile, encoding:.utf8)
		let openTx = try self.eventsEngine.transact(readOnly:false)
		try self.eventsEngine.profilesEngine.setPublicKeys([self.keypair.pubkey:newCurrentUserProfileInfo], asOf: [self.keypair.pubkey:newDAte], tx: openTx)
		var getRelays = try self.eventsEngine.relaysEngine.getRelays(pubkey:self.keypair.pubkey, tx:openTx)
		let getEvent = try self.generateMetadataEvent(content: newCurrentUserProfileInfo, with: newDAte)
		try self.eventsEngine.relaysEngine.write(event:getEvent, to:getRelays, tx:openTx)
		try openTx.commit()
	}
	
	@MainActor func sendTextNoteContentToAllRelays(_ content:String) throws {
		if content.filter({ $0.isWhitespace == false }).count == 0 {
			return
		}
		let getEvent = try self.generateContentEvent(content:content)
		let openTx = try self.eventsEngine.transact(readOnly:false)
		var getRelays = try self.eventsEngine.relaysEngine.getRelays(pubkey:self.keypair.pubkey, tx:openTx)
		try self.eventsEngine.relaysEngine.write(event:getEvent, to:getRelays, tx:openTx)
		try openTx.commit()
	}
	

	func getHomeTimelineState(anchor:DBUX.DatedNostrEventUID?, direction:UI.TimelineViewModel.ScrollDirection, limit:UInt16) throws -> ([nostr.Event], [nostr.Key:nostr.Profile]) {
		let tltx = try eventsEngine.transact(readOnly:true)
		var buildUsers = Set<nostr.Key>()
		let events = try eventsEngine.timelineEngine.readEvents(from:anchor, direction: direction, usersOut:&buildUsers, tx:tltx, filter: { nostrID in
			return true
		})
		let profiles = try self.eventsEngine.profilesEngine.getPublicKeys(publicKeys:buildUsers, tx: tltx)
		try tltx.commit()
		return (events.sorted(by: { $0.created < $1.created }), profiles)
	}

	func buildMainUserFilters() throws -> [nostr.Filter] {
		let newTransaction = try self.eventsEngine.transact(readOnly:true)
		// get the friends list
		let myFriends = try self.eventsEngine.followsEngine.getFollows(pubkey:self.keypair.pubkey, tx:newTransaction)
		try newTransaction.commit()
		
		let friendString = myFriends.compactMap({ $0.description })
		
		// build the contacts filter
		var contactsFilter = nostr.Filter()
		contactsFilter.authors = Array(friendString)
		contactsFilter.kinds = [.metadata, .contacts]
		
		var homeFilter = nostr.Filter()
		homeFilter.kinds = [.text_note, .like, .boost]
		homeFilter.authors = Array(friendString)
		
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

		// // create "notifications" filter
		// var notificationsFilter = nostr.Filter()
		// notificationsFilter.kinds = [.like, .boost, .text_note, .zap]
		// notificationsFilter.limit = 500

		// return [contactsFilter]
		return [contactsFilter, blocklistFilter, dmsFilter, ourDMsFilter, homeFilter]
	}
	
	deinit {
		mainTask!.cancel()
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
	struct URLHash: MDB_convertible, MDB_comparable, Hashable, Equatable, Comparable {
		fileprivate static func produceHash(from url:String) throws -> Data {
			var hasher = try Blake2bHasher(outputLength: 32)
			try Data(url.utf8).withUnsafeBytes { relayBytes in
				try hasher.update(relayBytes)
			}
			return try hasher.export()
		}

		var bytes: (
			UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
			UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
			UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
			UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
		) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

		@usableFromInline init(rawHashData: Data) {
			guard rawHashData.count == MemoryLayout<Self>.size else {
				return
			}
			rawHashData.withUnsafeBytes { byteBuffer in
				memcpy(&bytes, byteBuffer, MemoryLayout<Self>.size)
			}
		}
		@usableFromInline init(_ string: String) throws {
			self = .init(rawHashData: try Self.produceHash(from: string))
		}
		@usableFromInline init() {}
		@usableFromInline init(_ value: MDB_val) {
			let totalSize = value.mv_size
			guard totalSize == MemoryLayout<Self>.size else {
				return
			}
			let bytes = value.mv_data!.assumingMemoryBound(to: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
																 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
																 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
																 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8).self)
			self.bytes = bytes.pointee
		}
		@usableFromInline func asMDB_val<R>(_ valFunc: (inout MDB_val) throws -> R) rethrows -> R {
			try withUnsafePointer(to: self) { unsafePointer in
				var val = MDB_val(mv_size: MemoryLayout<Self>.size, mv_data: UnsafeMutableRawPointer(mutating: unsafePointer))
				return try valFunc(&val)
			}
		}

		@usableFromInline static func < (lhs: Self, rhs: Self) -> Bool {
			return lhs.asMDB_val { lhsVal in
				rhs.asMDB_val { rhsVal in
					Self.mdbCompareFunction(&lhsVal, &rhsVal) < 0
				}
			}
		}
		@usableFromInline static func == (lhs: Self, rhs: Self) -> Bool {
			return lhs.asMDB_val { lhsVal in
				rhs.asMDB_val { rhsVal in
					Self.mdbCompareFunction(&lhsVal, &rhsVal) == 0
				}
			}
		}

		public func hash(into hasher: inout Hasher) {
			self.asMDB_val { selfVal in
				hasher.combine(bytes: UnsafeRawBufferPointer(start:selfVal.mv_data, count: MemoryLayout<Self>.size))
			}
		}

		@usableFromInline static let mdbCompareFunction: @convention(c) (UnsafePointer<MDB_val>?, UnsafePointer<MDB_val>?) -> Int32 = { a, b in
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


extension DBUX {
	static func generateMainSubscription(pubkey:nostr.Key, following:Set<nostr.Key>) -> nostr.Subscribe {
		var homeFilter = nostr.Filter()
		homeFilter.kinds = [.text_note, .like, .boost, .metadata, .contacts]
		homeFilter.authors = Array(following.compactMap { $0.description })
		return nostr.Subscribe(sub_id: "_ux_home_\(pubkey.description.prefix(10))", filters: [homeFilter])
	}
}

extension DBUX {
	fileprivate func generateContactEvent(contacts followsList:Set<nostr.Key>, relays getRelays:Set<String>) throws -> nostr.Event {
		var newEvent = nostr.Event()
		newEvent.pubkey = self.keypair.pubkey
		newEvent.kind = .contacts
		// generate the list of people we are following
		newEvent.tags = followsList.compactMap({ nostr.Event.Tag.fromPublicKey($0) })
		
		var buildRelays = [String:[String:Bool]]()
		for curRelay in getRelays {
			buildRelays[curRelay] = ["read":true, "write":true]
		}
		let encoded = try JSONEncoder().encode(buildRelays)
		newEvent.content = String(data:encoded, encoding:.utf8)!
		try newEvent.computeUID()
		try newEvent.sign(privateKey:self.keypair.privkey)
		return newEvent
	}
	
	fileprivate func generateContentEvent(content:String) throws -> nostr.Event {
		var newEvent = nostr.Event()
		newEvent.pubkey = self.keypair.pubkey
		newEvent.kind = .text_note
		
		newEvent.content = content
		try newEvent.computeUID()
		try newEvent.sign(privateKey:self.keypair.privkey)
		return newEvent
	}
	
	fileprivate func generateMetadataEvent(content:nostr.Profile, with date:DBUX.Date) throws -> nostr.Event {
		var newEvent = nostr.Event()
		newEvent.pubkey = self.keypair.pubkey
		newEvent.kind = .metadata
		newEvent.created = date
		let encoder = JSONEncoder()
		let data = try encoder.encode(content)
		newEvent.content = String(data:data, encoding:.utf8)!
		try newEvent.computeUID()
		try newEvent.sign(privateKey:self.keypair.privkey)
		return newEvent
	}
	
	fileprivate func generateDirectMessage(content:String, to publicKey:nostr.Key, tags:[nostr.Event.Tag], createdOn:DBUX.Date) throws -> nostr.Event {
		let iv = random_bytes(count:16).bytes
		guard let shared_sec = try nostr.KeyPair.getSharedSecret(from:self.keypair) else {
			throw Error.unableToEncrypt
		}
		let utf8_message = Data(content.utf8).bytes
		guard let enc_message = aes_encrypt(data: utf8_message, iv: iv, shared_sec: shared_sec) else {
			throw Error.unableToEncrypt
		}
		
		let enc_content = encode_dm_base64(content: enc_message.bytes, iv: iv.bytes)
		var newEvent = nostr.Event()
		newEvent.pubkey = self.keypair.pubkey
		newEvent.kind = .dm
		newEvent.created = createdOn
		newEvent.content = enc_content
		try newEvent.computeUID()
		try newEvent.sign(privateKey:self.keypair.privkey)
		return newEvent
	}
}
