//
//  KeyPair.swift
//  topaz
//
//  Created by Tanner Silva on 4/13/23.
//

import Foundation
import QuickLMDB
import secp256k1

extension nostr {
	struct Key:MDB_convertible, MDB_comparable, LosslessStringConvertible, Hashable, Equatable, Comparable {
		static func nullKey() -> Self {
			return Self()
		}
		var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
		
		// Lexigraphical sorting here
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

		// LosslessStringConvertible (hex encoding)
		@usableFromInline var description: String {
			get {
				hex_encode(self.exportData())
			}
		}
		@usableFromInline internal init?(_ description:String) {
			guard let asBytes = hex_decode(description) else {
				return nil
			}
			guard asBytes.count == MemoryLayout<Self>.size else {
				return nil
			}
			self = Self.init(Data(asBytes))
		}

		// initialize a null structure
		init() {}
		
		// initialize a key from the contents of a byte buffer
		init<C>(_ bytes:C) where C:ContiguousBytes {
			bytes.withUnsafeBytes { byteBuff in
				_ = memcpy(&self.bytes, byteBuff.baseAddress, byteBuff.count)
			}
		}

		// MDB_convertible
		@usableFromInline internal init?(_ value: MDB_val) {
			guard value.mv_size == MemoryLayout<Self>.size else {
				return nil
			}
			_ = memcpy(&bytes, value.mv_data, MemoryLayout<Self>.size)
		}
		public func asMDB_val<R>(_ valFunc: (inout MDB_val) throws -> R) rethrows -> R {
			return try withUnsafePointer(to: bytes, { unsafePointer in
				var val = MDB_val(mv_size:MemoryLayout<Self>.size, mv_data: UnsafeMutableRawPointer(mutating: unsafePointer))
				return try valFunc(&val)
			})
		}

		// Equatable
		@usableFromInline static func == (lhs: Self, rhs: Self) -> Bool {
			return lhs.asMDB_val({ lhsVal in
				return rhs.asMDB_val({ rhsVal in
					return Self.mdbCompareFunction(&lhsVal, &rhsVal) == 0
				})
			})
		}
		
		// Comparable
		@usableFromInline static func < (lhs: Self, rhs: Self) -> Bool {
			return lhs.asMDB_val({ lhsVal in
				return rhs.asMDB_val({ rhsVal in
					return Self.mdbCompareFunction(&lhsVal, &rhsVal) < 0
				})
			})
		}

		// Hashable
		public func hash(into hasher:inout Hasher) {
			withUnsafePointer(to:bytes) { byteBuff in
				for i in 0..<MemoryLayout<Self>.size {
					hasher.combine(byteBuff.advanced(by: i))
				}
			}
		}
		
		/// Export the hash as a Data struct
		public func exportData() -> Data {
			withUnsafePointer(to:bytes) { byteBuff in
				return Data(bytes:byteBuff, count:MemoryLayout<Self>.size)
			}
		}
	}

	struct KeyPair:MDB_convertible, MDB_comparable, Equatable, Comparable, Hashable {
		static func generateNew() throws -> Self {
			let genesis = try secp256k1.Signing.PrivateKey()
			let privKey = Key(genesis.rawRepresentation)
			let pubKey = Key(genesis.publicKey.xonly.bytes)
			return Self(pubkey:pubKey, privkey:privKey)
		}

		// Lexigraphical sorting here
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

		let pubkey:Key
		let privkey:Key
		
		init(pubkey:Key, privkey:Key) {
			self.pubkey = pubkey
			self.privkey = privkey
		}

		// MDB_convertible
		@usableFromInline internal init?(_ value: MDB_val) {
			guard value.mv_size == MemoryLayout<Self>.size else {
				return nil
			}
			self = value.mv_data!.assumingMemoryBound(to: Self.self).pointee
		}
		public func asMDB_val<R>(_ valFunc: (inout MDB_val) throws -> R) rethrows -> R {
			return try withUnsafePointer(to:self, { unsafePointer in
				var val = MDB_val(mv_size:MemoryLayout<Self>.size, mv_data: UnsafeMutableRawPointer(mutating: unsafePointer))
				return try valFunc(&val)
			})
		}

		// Equatable
		@usableFromInline static func == (lhs: Self, rhs: Self) -> Bool {
			return lhs.asMDB_val({ lhsVal in
				return rhs.asMDB_val({ rhsVal in
					return Self.mdbCompareFunction(&lhsVal, &rhsVal) == 0
				})
			})
		}
		
		// Comparable
		@usableFromInline static func < (lhs: Self, rhs: Self) -> Bool {
			return lhs.asMDB_val({ lhsVal in
				return rhs.asMDB_val({ rhsVal in
					return Self.mdbCompareFunction(&lhsVal, &rhsVal) < 0
				})
			})
		}

		// Hashable
		public func hash(into hasher:inout Hasher) {
			withUnsafePointer(to:self) { byteBuff in
				for i in 0..<MemoryLayout<Self>.size {
					hasher.combine(byteBuff.advanced(by: i))
				}
			}
		}
	}
}
