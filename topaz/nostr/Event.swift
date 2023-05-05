//
//  Event.swift
//  topaz
//
//  Created by Tanner Silva on 3/7/23.
//

import Foundation
import QuickLMDB
import CommonCrypto
import secp256k1
import secp256k1_implementation
import CryptoKit
import SwiftBlake2

extension nostr {
	enum EncEncoding {
		case base64
		case bech32
	}

	/// a reference to another event
	struct ReferenceID:Hashable, Equatable, Identifiable {
		let ref_id:String
		let relay_id:String?
		let key:String
		
		init(ref_id:String, relay_id:String?, key:String) {
			self.ref_id = ref_id
			self.relay_id = relay_id
			self.key = key
		}
		
		init?(_ arr:[String]) {
			if arr.count == 0 {
				return nil
			}
			if arr.count == 1 {
				return nil
			}

			var relay_id: String? = nil
			if arr.count > 2 {
				relay_id = arr[2]
			}
			self.ref_id = arr[1]
			self.relay_id = relay_id
			self.key = arr[0]
		}
		
		var id:String {
			return ref_id
		}
		
		func toTag() throws -> Event.Tag {
			var tag = [key, ref_id]
			if let rid = relay_id {
				tag.append(rid)
			}
			return Event.Tag(tag)
		}
	}
	
	@usableFromInline struct Event:Codable {
		static let logger = Topaz.makeDefaultLogger(label:"nostr.Event")
		
		///
		enum ValidationResult:UInt8 {
			case ok
			case bad_id
			case bad_sig
		}

		///
		enum Block {
			case text(String)
			case mention(Mention)
			case hashtag(String)
			case url(URL)
			case invoice(Invoice)
		}
		
		///
		@frozen @usableFromInline enum Kind:Int, Equatable, MDB_convertible, Codable {
			case metadata = 0
			case text_note = 1
			case recommended_relay = 2
			case contacts = 3
			case dm = 4
			case delete = 5
			case boost = 6
			case like = 7
			case channel_create = 8
			case channel_meta = 9
			case chat = 42
			case list = 40000 // (?)
			case zap = 9735
			case zap_request = 9734
			case private_zap = 9733 // I think?
			case list_mute = 10000
			case list_pin = 10001
			case list_categorized = 30000
			case list_categorized_bookmarks = 30001

			@usableFromInline init?(_ value:MDB_val) {
				guard MemoryLayout<Int>.size == value.mv_size else {
					return nil
				}
				guard let asSelf = Self(rawValue:value.mv_data.bindMemory(to:Int.self, capacity:1).pointee) else {
					return nil
				}
				self = asSelf
			}
			@usableFromInline func asMDB_val<R>(_ valFunc:(inout MDB_val) throws -> R) rethrows -> R {
				return try withUnsafePointer(to:self.rawValue) { rawVal in
					var val = MDB_val(mv_size:MemoryLayout<Int>.size, mv_data:UnsafeMutableRawPointer(mutating: rawVal))
					return try valFunc(&val)
				}
			}
		}

		struct Tag:Codable {
			enum Error:Swift.Error {
				case unknownTagKind
			}
			
			static func fromPublicKey(_ key:nostr.Key) -> Tag {
				return Self(["p", key.description])
			}
			
			static let logger = Topaz.makeDefaultLogger(label:"nostr.Event.Tag")

			enum Kind:Codable, LosslessStringConvertible, Equatable {
				/// a tag that references another nostr event
				case event
				/// a tag that references a user
				case pubkey

				/// any kind of tag that is not supported in this software
				case unknown(String)

				var description:String {
					get {
						switch self {
						case .event:
							return "e"
						case .pubkey:
							return "p"
						case .unknown(let str):
							return str
						}
					}
				}
				init(_ description:String) {
					switch description {
					case "e":
						self = .event
					case "p":
						self = .pubkey
					default:
						self = .unknown(description)
					}
				}

				init(from decoder: Decoder) throws {
					let container = try decoder.singleValueContainer()
					let rawValue = try container.decode(String.self)
					switch rawValue {
					case "e":
						self = .event
					case "p":
						self = .pubkey
					default:
						self = .unknown(rawValue)
					}
				}

				func encode(to encoder: Encoder) throws {
					var container = encoder.singleValueContainer()
					switch self {
					case .event:
						try container.encode("e")
					case .pubkey:
						try container.encode("p")
					case .unknown(let str):
						try container.encode(str)
					}
				}

				static func == (lhs: Self, rhs: Self) -> Bool {
					switch (lhs, rhs) {
					case (.event, .event):
						return true
					case (.pubkey, .pubkey):
						return true
					case (.unknown(let lstr), .unknown(let rstr)):
						return lstr == rstr
					default:
						return false
					}
				}
			}

			let kind:Kind
			let info:[String]
			
			var count:Int {
				return info.count + 1
			}
			
			init(_ array:[String]) {
				let makeKind = Kind(array[0])
				self.kind = makeKind
				self.info = Array(array[array.startIndex.advanced(by: 1)..<array.count])
			}

			init(from decoder: Decoder) throws {
				do {
					var container = try decoder.unkeyedContainer()
					self.kind = try container.decode(Kind.self)
					var otherValues:[String] = []
					while !container.isAtEnd {
						otherValues.append(try container.decode(String.self))
					}
					self.info = otherValues
				} catch let error {
					Self.logger.debug("error decoding tag.", metadata:["error": "\(error)"])
					throw error
				}
			}
			func encode(to encoder: Encoder) throws {
				do {
					var container = encoder.unkeyedContainer()
					try container.encode(kind)
					for curVal in info {
						try container.encode(curVal)
					}
				} catch let error {
					Self.logger.debug("error encoding tag.", metadata:["error": "\(error)"])
					throw error
				}
			}
			
			subscript(_ index:Int) -> String {
				get {
					if index == 0 {
						return kind.description
					} else {
						return info[index-1]
					}
				}
			}
			
			func toArray() -> [String] {
				var buildArray = [kind.description]
				buildArray.append(contentsOf:info)
				return buildArray
			}
			
			func toReference() -> ReferenceID {
				var relay_id:String? = nil
				if info.count > 2 {
					relay_id = info[2]
				}

				return ReferenceID(ref_id:info[1], relay_id:relay_id, key:self.kind.description)
			}
		}

		enum CodingKeys:String, CodingKey {
			case uid = "id"
			case sig = "sig"
			case tags = "tags"
			case boosted_by = "boosted_by"
			case pubkey = "pubkey"
			case created = "created_at"
			case kind = "kind"
			case content = "content"
		}
		
		private static let df = ISO8601DateFormatter()

		var uid = UID.nullUID()
		var sig = "* a very invalid sig lol *"
		var tags = [Tag]()

		var pubkey:Key = nostr.Key.nullKey()
		var created = DBUX.Date()
		var kind = Kind.text_note
		var content:String = ""
		
		// used to render the UI during development
		static func createTestPost() -> Self {
			return Self(uid:UID.nullUID(), sig:"", tags:[], boosted_by: nil, pubkey:nostr.Key.nullKey(), created:DBUX.Date(Date(timeIntervalSinceNow:-300)), kind:Kind.text_note, content:"oh jeez look here at all this content wowweee")
		}
		
		init() {}
		
		fileprivate init(uid:UID, sig:String, tags:[Tag], boosted_by:String?, pubkey:Key, created:DBUX.Date, kind:Kind, content:String) {
			self.uid = uid
			self.sig = sig
			self.tags = tags
			self.pubkey = pubkey
			self.created = created
			self.kind = kind
			self.content = content
		}

		@usableFromInline init(from decoder:Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			self.uid = try container.decode(UID.self, forKey: .uid)
			let getSig = try container.decode(String.self, forKey: .sig)
			self.sig = getSig
			self.tags = try container.decode([Tag].self, forKey: .tags)
			self.pubkey = try container.decode(Key.self, forKey: .pubkey)
			let getTI = try container.decode(Int.self, forKey: .created)
			let getCreateDate = Date(timeIntervalSince1970:TimeInterval(getTI))
			self.created = DBUX.Date(getCreateDate)
			self.kind = Kind(rawValue:try! container.decode(Int.self, forKey: .kind))!
			self.content = try container.decode(String.self, forKey: .content)
		}

		@usableFromInline func encode(to encoder:Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try! container.encode(uid, forKey: .uid)
			try! container.encode(sig, forKey: .sig)
			try! container.encode(tags, forKey: .tags)
			try! container.encode(pubkey, forKey: .pubkey)
			try! container.encode(Int(created.exportDate().timeIntervalSince1970), forKey: .created)
			try! container.encode(kind.rawValue, forKey: .kind)
			try! container.encode(content, forKey: .content)
		}
		
		func getReferencedIDs(_ key:String = "e") -> [ReferenceID] {
			return tags.reduce(into: []) { (acc, tag) in
				if tag.count >= 2 && tag.kind.description == key {
					var relay_id: String? = nil
					if tag.count >= 3 {
						relay_id = tag[2]
					}
					acc.append(ReferenceID(ref_id: tag[1], relay_id:relay_id, key: key))
				}
			}
		}
		func getContent(_ privkey:String?) -> String {
			if self.kind == .dm {
				return decrypted(privkey: privkey) ?? "*failed to decrypt content*"
			}
			return content
		}
		func decrypted(privkey: String?) -> String? {
			guard let key = privkey else {
				return nil
			}
			
			guard let our_pubkey = privkey_to_pubkey(privkey: key) else {
				return nil
			}
			
			var pubkey = self.pubkey.description
			// This is our DM, we need to use the pubkey of the person we're talking to instead
			if our_pubkey == pubkey {
				guard let refkey = self.getReferencedIDs("e").first else {
					return nil
				}
				
				pubkey = refkey.ref_id
			}

			let dec = decrypt_dm(key, pubkey: pubkey, content: self.content, encoding: .base64)
			return dec
		}

	}
}

extension nostr.Event:Equatable {
	@usableFromInline static func == (lhs:nostr.Event, rhs:nostr.Event) -> Bool {
		return lhs.uid == rhs.uid
	}
}

extension nostr.Event:Hashable {
	@usableFromInline func hash(into hasher:inout Hasher) {
		hasher.combine(uid)
	}
}

extension nostr.Event:Identifiable {
	@usableFromInline var id:String {
		return self.uid.description
	}
}

extension nostr.Event {
	@frozen @usableFromInline struct UID:MDB_convertible, MDB_comparable, Hashable, Equatable, Comparable, LosslessStringConvertible, Codable {
		enum Error:Swift.Error {
			case invalidStringLength(String)
		}

		static func nullUID() -> Self {
			return Self()
		}
		
		static func generatedFrom(event:nostr.Event) throws -> Self {
			let commitment = try event.commitment()
			let hashed = sha256(commitment)
			return Self(hashed)
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

		@usableFromInline static func == (lhs: nostr.Event.UID, rhs: nostr.Event.UID) -> Bool {
			return lhs.asMDB_val({ lhsVal in
				return rhs.asMDB_val({ rhsVal in
					return Self.mdbCompareFunction(&lhsVal, &rhsVal) == 0
				})
			})
		}
		
		@usableFromInline static func < (lhs: nostr.Event.UID, rhs: nostr.Event.UID) -> Bool {
			return lhs.asMDB_val({ lhsVal in
				return rhs.asMDB_val({ rhsVal in
					return Self.mdbCompareFunction(&lhsVal, &rhsVal) < 0
				})
			})
		}

		var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
		
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

		/// Initialize from Data containing SHA256 hash
		internal init(_ hashData: Data) {
			hashData.withUnsafeBytes({ byteBuffer in
				memcpy(&bytes, byteBuffer, MemoryLayout<Self>.size)
			})
		}

		/// Null Initializer
		fileprivate init() {}

		// MDB_convertible
		@usableFromInline internal init?(_ value: MDB_val) {
			guard value.mv_size == MemoryLayout<Self>.size else {
				return nil
			}
			_ = memcpy(&bytes, value.mv_data, MemoryLayout<Self>.size)
		}
		public func asMDB_val<R>(_ valFunc: (inout MDB_val) throws -> R) rethrows -> R {
			return try withUnsafePointer(to: bytes, { unsafePointer in
				var val = MDB_val(mv_size: MemoryLayout<Self>.size, mv_data: UnsafeMutableRawPointer(mutating: unsafePointer))
				return try valFunc(&val)
			})
		}
		
		// Hashable
		public func hash(into hasher:inout Hasher) {
			asMDB_val({ hashVal in
				hasher.combine(hashVal)
			})
		}
		
		/// Export the hash as a Data struct
		public func exportData() -> Data {
			withUnsafePointer(to:bytes) { byteBuff in
				return Data(bytes:byteBuff, count:MemoryLayout<Self>.size)
			}
		}
		
		/// Codable
		@usableFromInline init(from decoder:Decoder) throws {
			let container = try decoder.singleValueContainer()
			let asString = try container.decode(String.self)
			guard let makeSelf = Self(asString) else {
				throw Error.invalidStringLength(asString)
			}
			self = makeSelf
		}
		@usableFromInline  func encode(to encoder: Encoder) throws {
			var container = encoder.singleValueContainer()
			try container.encode(self.description)
		}
	}
}

extension nostr.Event {
	/// The result of validating an event.
	fileprivate func commitment() throws -> Data {
		let encoder = JSONEncoder()
		encoder.outputFormatting = .withoutEscapingSlashes
		let tagsString = String(data:try encoder.encode(self.tags), encoding:.utf8)!
		let buildContentString = try encoder.encode(self.content)
		let contentString = String(data:buildContentString, encoding:.utf8)!
		let commit = "[0,\"\(self.pubkey)\",\(Int64(self.created.exportDate().timeIntervalSince1970)),\(self.kind.rawValue),\(tagsString),\(contentString)]"
		return Data(commit.utf8)
	}
	mutating func computeUID() throws {
		self.uid = try UID.generatedFrom(event: self)
	}
	func validate() -> Result<ValidationResult, Swift.Error> {
		do {
			let raw_id = UID(sha256(try self.commitment()))
			if raw_id != self.uid {
				Self.logger.error("validation failed - uid mismatch")
				return .success(.bad_id)
			}
			guard var sig64 = hex_decode(self.sig) else {
				Self.logger.error("validation failed - could not hex decode signature")
				return .success(.bad_sig)
			}
			guard var ev_pubkey = hex_decode(self.pubkey.description) else {
				Self.logger.error("validation failed - could not hex decode public key")
				return .success(.bad_sig)
			}
			let ctx = try secp256k1.Context.create()
			var xonly_pubkey = secp256k1_xonly_pubkey.init()
			var ok = secp256k1_xonly_pubkey_parse(ctx, &xonly_pubkey, &ev_pubkey) != 0
			if !ok {
				Self.logger.error("validation failed - not ok?")
				return .success(.bad_sig)
			}
			var raw_id_bytes = raw_id.bytes
			ok = secp256k1_schnorrsig_verify(ctx, &sig64, &raw_id_bytes, MemoryLayout<UID>.size, &xonly_pubkey) > 0
			let result:ValidationResult = ok ? .ok : .bad_sig
			return .success(result)
		} catch let error {
			return .failure(error)
		}
	}
	mutating func sign(privateKey:nostr.Key) throws {
		let key = try secp256k1.Signing.PrivateKey(rawRepresentation: privateKey.bytes)

		// Extra params for custom signing

		var aux_rand = random_bytes(count: 64)
		var digest = self.uid.exportData().bytes

		// API allows for signing variable length messages
		let signature = try key.schnorr.signature(message: &digest, auxiliaryRand: &aux_rand)

		self.sig = hex_encode(signature.rawRepresentation)
	}
	func firstEventTag() -> String? {
		for tag in tags {
			if case .event = tag.kind {
				return tag.info[0]
			}
		}
		return nil
	}
	func lastEventTag() -> String? {
		for tag in tags.reversed() {
			if case .event = tag.kind {
				return tag.info[0]
			}
		}
		return nil
	}
	func innerEvent() -> nostr.Event? {
		if self.kind == .boost {
			let jsonData = Data(self.content.utf8)
			return try? JSONDecoder().decode(nostr.Event.self, from:jsonData)
		}
		return nil
	}
	func innterEventOrSelf() -> nostr.Event {
		guard let inner_ev = innerEvent() else {
			return self
		}
		return inner_ev
	}
	func firstErefMention(privkey:String?) -> nostr.Mention? {
		return first_eref_mention(ev:self, privkey:privkey)
	}
	func blocks() -> [Block] {
		return parse_mentions(content:content, tags:self.tags)
	}
	func getContent(privkey:String) -> String {
		if kind == .dm {
			return decrypted(privkey:privkey) ?? "*failed*"
		}
		return content
	}
	func getEventReferences() -> [EventReference] {
		return interpret_event_refs(blocks:self.blocks(), tags:self.tags.compactMap({ $0.toArray() }))
	}
	func isReply() -> Bool {
		return self.getReferencedIDs("e").count > 0
	}
}

extension nostr.KeyPair {
	public static func getSharedSecret(from keypair:nostr.KeyPair) throws -> [UInt8]? {
		let privkey_bytes = Data(keypair.privkey.bytes).bytes
		var pk_bytes = Data(keypair.pubkey.bytes).bytes
		pk_bytes.insert(2, at: 0)
		
		var publicKey = secp256k1_pubkey()
		var shared_secret = [UInt8](repeating: 0, count: 32)

		var ok =
			secp256k1_ec_pubkey_parse(
				try secp256k1.Context.create(),
				&publicKey,
				pk_bytes,
				pk_bytes.count) != 0

		if !ok {
			return nil
		}

		ok = secp256k1_ecdh(
			try secp256k1.Context.create(),
			&shared_secret,
			&publicKey,
			privkey_bytes, {(output,x32,_,_) in
				memcpy(output,x32,32)
				return 1
			}, nil) != 0

		if !ok {
			return nil
		}

		return shared_secret
	}
}

func decrypt_dm(_ privkey: String?, pubkey: String, content:String, encoding:nostr.EncEncoding) -> String? {
	guard let privkey = privkey else {
		return nil
	}
	guard let shared_sec = try? nostr.KeyPair.getSharedSecret(from: nostr.KeyPair(pubkey:nostr.Key(pubkey)!, privkey:nostr.Key(privkey)!)) else {
		return nil
	}
	guard let dat = (encoding == .base64 ? decode_dm_base64(content) : decode_dm_bech32(content)) else {
		return nil
	}
	guard let dat = aes_decrypt(data: dat.content, iv: dat.iv, shared_sec: shared_sec) else {
		return nil
	}
	return String(data: dat, encoding: .utf8)
}

func decrypt_note(our_privkey: String, their_pubkey: String, enc_note: String, encoding: nostr.EncEncoding) -> nostr.Event? {
	guard let dec = decrypt_dm(our_privkey, pubkey:their_pubkey, content: enc_note, encoding: encoding) else {
		return nil
	}
	
	return decode_nostr_event_json(json: dec)
}

func decrypt_private_zap(our_privkey: String, zapreq:nostr.Event, target:Zap.Target) -> nostr.Event? {
	guard let anon_tag = zapreq.tags.first(where: { t in t.count >= 2 && t[0] == "anon" }) else {
		return nil
	}
	
	let enc_note = anon_tag[1]
	
	var note = decrypt_note(our_privkey: our_privkey, their_pubkey: zapreq.pubkey.description, enc_note: enc_note, encoding: .bech32)
	
	// check to see if the private note was from us
	if note == nil {
		guard let our_private_keypair = generate_private_keypair(our_privkey: our_privkey, id: target.id, created_at: Int64(zapreq.created.exportDate().timeIntervalSince1970)) else{
			return nil
		}
		// use our private keypair and their pubkey to get the shared secret
		note = decrypt_note(our_privkey: our_private_keypair.privkey, their_pubkey: target.pubkey, enc_note: enc_note, encoding: .bech32)
	}
	
	guard let note else {
		return nil
	}
	
	guard note.kind == .private_zap else {
		return nil
	}
	
	let zr_etag = zapreq.getReferencedIDs("e").first
	let note_etag = note.getReferencedIDs("e").first
	
	guard zr_etag == note_etag else {
		return nil
	}
	
	let zr_ptag = zapreq.getReferencedIDs("p").first
	let note_ptag = note.getReferencedIDs("p").first
	
	guard let zr_ptag, let note_ptag, zr_ptag == note_ptag else {
		return nil
	}
	
	do {
		guard case .success(.ok) = zapreq.validate() else {
			return nil
		}
	} catch {
		return nil
	}
	return note
}



func sha256(_ data: Data) -> Data {
	var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
	data.withUnsafeBytes {
		_ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
	}
	return Data(hash)
}


func encode_json<T: Encodable>(_ val: T) -> String? {
	let encoder = JSONEncoder()
	encoder.outputFormatting = .withoutEscapingSlashes
	return (try? encoder.encode(val)).map { String(decoding: $0, as: UTF8.self) }
}

func decode_nostr_event_json(json: String) -> nostr.Event? {
	return decode_json(json)
}

func decode_json<T: Decodable>(_ val: String) -> T? {
	return try? JSONDecoder().decode(T.self, from: Data(val.utf8))
}

func decode_data<T: Decodable>(_ data: Data) -> T? {
	let decoder = JSONDecoder()
	do {
		return try decoder.decode(T.self, from: data)
	} catch {}

	return nil
}

struct DirectMessageBase64 {
	let content: [UInt8]
	let iv: [UInt8]
}

func encode_dm_bech32(content: [UInt8], iv: [UInt8]) -> String {
	let content_bech32 = bech32_encode(hrp: "pzap", content)
	let iv_bech32 = bech32_encode(hrp: "iv", iv)
	return content_bech32 + "_" + iv_bech32
}

func decode_dm_bech32(_ all: String) -> DirectMessageBase64? {
	let parts = all.split(separator: "_")
	guard parts.count == 2 else {
		return nil
	}
	
	let content_bech32 = String(parts[0])
	let iv_bech32 = String(parts[1])
	
	guard let content_tup = try? bech32_decode(content_bech32) else {
		return nil
	}
	guard let iv_tup = try? bech32_decode(iv_bech32) else {
		return nil
	}
	guard content_tup.hrp == "pzap" else {
		return nil
	}
	guard iv_tup.hrp == "iv" else {
		return nil
	}
	
	return DirectMessageBase64(content: content_tup.data.bytes, iv: iv_tup.data.bytes)
}

func encode_dm_base64(content: [UInt8], iv: [UInt8]) -> String {
	let content_b64 = base64_encode(content)
	let iv_b64 = base64_encode(iv)
	return content_b64 + "?iv=" + iv_b64
}

func decode_dm_base64(_ all: String) -> DirectMessageBase64? {
	let splits = Array(all.split(separator: "?"))

	if splits.count != 2 {
		return nil
	}

	guard let content = base64_decode(String(splits[0])) else {
		return nil
	}

	var sec = String(splits[1])
	if !sec.hasPrefix("iv=") {
		return nil
	}

	sec = String(sec.dropFirst(3))
	guard let iv = base64_decode(sec) else {
		return nil
	}

	return DirectMessageBase64(content: content, iv: iv)
}

func base64_encode(_ content: [UInt8]) -> String {
	return Data(content).base64EncodedString()
}

func base64_decode(_ content: String) -> [UInt8]? {
	guard let dat = Data(base64Encoded: content) else {
		return nil
	}
	return dat.bytes
}

func aes_decrypt(data: [UInt8], iv: [UInt8], shared_sec: [UInt8]) -> Data? {
	return aes_operation(operation: CCOperation(kCCDecrypt), data: data, iv: iv, shared_sec: shared_sec)
}

func aes_encrypt(data: [UInt8], iv: [UInt8], shared_sec: [UInt8]) -> Data? {
	return aes_operation(operation: CCOperation(kCCEncrypt), data: data, iv: iv, shared_sec: shared_sec)
}

func aes_operation(operation: CCOperation, data: [UInt8], iv: [UInt8], shared_sec: [UInt8]) -> Data? {
	let data_len = data.count
	let bsize = kCCBlockSizeAES128
	let len = Int(data_len) + bsize
	var decrypted_data = [UInt8](repeating: 0, count: len)

	let key_length = size_t(kCCKeySizeAES256)
	if shared_sec.count != key_length {
		assert(false, "unexpected shared_sec len: \(shared_sec.count) != 32")
		return nil
	}

	let algorithm: CCAlgorithm = UInt32(kCCAlgorithmAES128)
	let options:   CCOptions   = UInt32(kCCOptionPKCS7Padding)

	var num_bytes_decrypted :size_t = 0

	let status = CCCrypt(operation,  /*op:*/
						 algorithm,  /*alg:*/
						 options,    /*options:*/
						 shared_sec, /*key:*/
						 key_length, /*keyLength:*/
						 iv,         /*iv:*/
						 data,       /*dataIn:*/
						 data_len, /*dataInLength:*/
						 &decrypted_data,/*dataOut:*/
						 len,/*dataOutAvailable:*/
						 &num_bytes_decrypted/*dataOutMoved:*/
	)

	if UInt32(status) != UInt32(kCCSuccess) {
		return nil
	}

	return Data(bytes: decrypted_data, count: num_bytes_decrypted)

}


func first_eref_mention(ev:nostr.Event, privkey: String?) -> nostr.Mention? {
	let blocks = ev.blocks().filter { block in
		guard case .mention(let mention) = block else {
			return false
		}
		
		guard case .event = mention.type else {
			return false
		}
		
		if mention.ref.key != "e" {
			return false
		}
		
		return true
	}
	
	/// MARK: - Preview
	if let firstBlock = blocks.first, case .mention(let mention) = firstBlock, mention.ref.key == "e" {
		return mention
	}
	
	return nil
}

func generate_private_keypair(our_privkey: String, id: String, created_at: Int64) -> KeyPair? {
	let to_hash = our_privkey + id + String(created_at)
	guard let dat = to_hash.data(using: .utf8) else {
		return nil
	}
	let privkey_bytes = sha256(dat)
	let privkey = hex_encode(privkey_bytes)
	guard let pubkey = privkey_to_pubkey(privkey: privkey) else {
		return nil
	}
	
	return KeyPair(pubkey: pubkey, privkey: privkey)
}

func interpret_event_refs(blocks:[nostr.Event.Block], tags:[[String]]) -> [EventReference] {
	if tags.count == 0 {
		return []
	}
	
	/// build a set of indices for each event mention
	let mention_indices = build_mention_indices(blocks, type: .event)
	
	/// simpler case with no mentions
	if mention_indices.count == 0 {
		let ev_refs = get_referenced_ids(tags: tags, key: "e")
		return interp_event_refs_without_mentions(ev_refs)
	}
	
	return interp_event_refs_with_mentions(tags: tags, mention_indices: mention_indices)
}


func event_is_reply(_ ev:nostr.Event, privkey: String?) -> Bool {
	return ev.getEventReferences().contains { evref in
		return evref.is_reply != nil
	}
}
