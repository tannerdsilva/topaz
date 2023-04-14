import QuickLMDB
import struct Foundation.TimeInterval
import struct Foundation.UUID
import struct Foundation.Data
import Darwin
import Logging
import class Foundation.FileManager
import struct Foundation.URL
import SwiftBlake2

// encompasses the user experience 
public struct DBUX:Based {
	let logger:Logger
	let base:URL
	
//	let relaysEngine:DBUX.RelaysEngine
	
	init(base:URL, keypair:KeyPair) throws {
		let makeLogger = Topaz.makeDefaultLogger(label:"dbux")
		self.logger = makeLogger
		let makeBase = base.appendingPathComponent("uid-\(keypair)", isDirectory:true)
		if FileManager.default.fileExists(atPath: makeBase.path) == false {
			try FileManager.default.createDirectory(atPath:makeBase.path, withIntermediateDirectories:false)
		}
		self.base = makeBase
//		let makeRelays:DBUX.RelaysEngine = try Topaz.launchExperienceEngine(DBUX.RelaysEngine.self, from:makeBase, for:nostr.Key(keypair.pubkey)!)
//		self.relaysEngine = makeRelays
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
		@usableFromInline let obj:nostr.Event.UID

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
			self.date = DBUX.Date(event.created)
			self.obj = event.uid
		}

		internal init(date: Date, obj:nostr.Event.UID) {
			self.date = date
			self.obj = obj
		}

		@usableFromInline internal init?(_ value: MDB_val) {
			let totalSize = value.mv_size
			guard totalSize > MemoryLayout<TimeInterval>.size else {
				return nil
			}
			guard let date = Self.dateFromMDBVal(value: value) else {
				return nil
			}
			guard let obj = Self.uidFromMDBVal(value: value) else {
				return nil
			}
			self.date = date
			self.obj = obj
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
			obj.asMDB_val({ objVal in
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
