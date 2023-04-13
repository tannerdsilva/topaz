import QuickLMDB
import struct Foundation.TimeInterval
import struct Foundation.UUID
import struct Foundation.Data
import Darwin

// encompasses the user experience 
public struct DBUX {}

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
	/*@frozen @usableFromInline internal struct UUID: MDB_convertible, MDB_comparable, LosslessStringConvertible, Hashable, Equatable, Comparable {
		static public func == (lhs:Self, rhs:Self) -> Bool {
			return lhs.asMDB_val({ lhsVal in
				return rhs.asMDB_val({ rhsVal in
					return Self.mdbCompareFunction(&lhsVal, &rhsVal) == 0
				})
			})
		}
		
		static public func < (lhs:Self, rhs:Self) -> Bool {
			return lhs.asMDB_val({ lhsVal in
				return rhs.asMDB_val({ rhsVal in
					return Self.mdbCompareFunction(&lhsVal, &rhsVal) < 0
				})
			})
		}
		
		fileprivate static let hashLength = 16

		var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

		// Initialize from UUID
		@usableFromInline internal init(_ uuid: Foundation.UUID) {
			self.bytes = uuid.uuid
		}

		public var description: String {
			let uuid = withUnsafePointer(to: bytes) { ptr -> uuid_t in
				return ptr.withMemoryRebound(to: UInt8.self, capacity: Self.hashLength) { bytePtr in
					return bytePtr.withMemoryRebound(to: uuid_t.self, capacity: 1) { uuidPtr in
						return uuidPtr.pointee
					}
				}
			}
			return Foundation.UUID(uuid: uuid).uuidString
		}

		public init?(_ description: String) {
			guard let uuid = Foundation.UUID(uuidString: description) else {
				return nil
			}
			self.init(uuid)
		}


		// Initialize from database
		@usableFromInline internal init?(_ value: MDB_val) {
			guard value.mv_size == Self.hashLength else {
				return nil
			}
			_ = memcpy(&bytes, value.mv_data, Self.hashLength)
		}

		// Encode into database
		public func asMDB_val<R>(_ valFunc: (inout MDB_val) throws -> R) rethrows -> R {
			return try withUnsafePointer(to: bytes, { unsafePointer in
				var val = MDB_val(mv_size: Self.hashLength, mv_data: UnsafeMutableRawPointer(mutating: unsafePointer))
				return try valFunc(&val)
			})
		}

		// Lexigraphical sorting here
		@usableFromInline static let mdbCompareFunction:@convention(c) (UnsafePointer<MDB_val>?, UnsafePointer<MDB_val>?) -> Int32 = { a, b in
			let aData = a!.pointee.mv_data!.assumingMemoryBound(to: UInt8.self)
			let bData = b!.pointee.mv_data!.assumingMemoryBound(to: UInt8.self)
			
			let minLength = min(a!.pointee.mv_size, b!.pointee.mv_size)
			let comparisonResult = memcmp(aData, bData, minLength)

			if comparisonResult != 0 {
				return Int32(comparisonResult)
			} else {
				// If the common prefix is the same, compare their lengths.
				return Int32(a!.pointee.mv_size) - Int32(b!.pointee.mv_size)
			}
		}

		// Hashable conformance
		public func hash(into hasher: inout Hasher) {
			withUnsafePointer(to:bytes, { unsafePointer in
				for i in 0..<Self.hashLength {
					hasher.combine(unsafePointer.advanced(by:i))
				}
			})
		}
	}*/
}
