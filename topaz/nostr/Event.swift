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

extension nostr {
	enum EncEncoding {
		case base64
		case bech32
	}

	/// a reference to another event
	struct Reference:Hashable, Equatable, Identifiable {
		let ref_id:String
		let relay_id:String?
		let key:String

		var id:String {
			return ref_id
		}
		
		func toTag() throws -> Event.Tag {
			var tag = [key, ref_id]
			if let rid = relay_id {
				tag.append(rid)
			}
			return try Event.Tag(tag)
		}
	}
	
	///
	struct Event:Codable {
		
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
		enum Kind:Int, Equatable, MDB_convertible {
			case set_metadata = 0
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
			case list = 40000
			case zap = 9735
			case zap_request = 9734
			case private_zap = 9733 // I think?
		}

		struct Tag:Codable {
			enum Error:Swift.Error {
				case unknownTagKind
			}
			static let logger = Topaz.makeDefaultLogger(label:"nostr.Event.Tag")

			enum Kind:String, Codable {
				/// a tag that references another nostr event
				case event = "e"
				/// a tag that references a user
				case pubkey = "p"
			}

			let kind:Kind
			let info:[String]
			
			var count:Int {
				return info.count + 1
			}
			
			init(_ array:[String]) throws {
				guard let makeKind = Kind(rawValue:array[0]) else {
					throw Error.unknownTagKind
				}
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
						return kind.rawValue
					} else {
						return info[index-1]
					}
				}
			}
			
			func toArray() -> [String] {
				var buildArray = [kind.rawValue]
				buildArray.append(contentsOf:info)
				return buildArray
			}
			
			func toReference() -> Reference {
				var relay_id:String? = nil
				if info.count > 2 {
					relay_id = info[2]
				}

				return Reference(ref_id:info[1], relay_id:relay_id, key:self.kind.rawValue)
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
		
		let uid:String
		let sig:String
		let tags:[Tag]
		let boosted_by:String?

		let pubkey:String
		let created:Date
		let kind:Kind
		let content:String

		init(from decoder:Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			self.uid = try container.decode(String.self, forKey: .uid)
			self.sig = try container.decode(String.self, forKey: .sig)
			self.tags = try container.decode([Tag].self, forKey: .tags)
			self.boosted_by = try container.decodeIfPresent(String.self, forKey: .boosted_by)
			self.pubkey = try container.decode(String.self, forKey: .pubkey)
			let getTI = try container.decode(TimeInterval.self, forKey: .created)
			self.created = Date(timeIntervalSince1970:getTI)
			self.kind = Kind(rawValue:try container.decode(Int.self, forKey: .kind))!
			self.content = try container.decode(String.self, forKey: .content)
		}

		func encode(to encoder:Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(uid, forKey: .uid)
			try container.encode(sig, forKey: .sig)
			try container.encode(tags, forKey: .tags)
			try container.encode(boosted_by, forKey: .boosted_by)
			try container.encode(pubkey, forKey: .pubkey)
			try container.encode(created.timeIntervalSince1970, forKey: .created)
			try container.encode(kind.rawValue, forKey: .kind)
			try container.encode(content, forKey: .content)
		}
		
		func getReferencedIDs(_ key:String = "e") -> [Reference] {
			return tags.reduce(into: []) { (acc, tag) in
				if tag.count >= 2 && tag.kind.rawValue == key {
					var relay_id: String? = nil
					if tag.count >= 3 {
						relay_id = tag[2]
					}
					acc.append(Reference(ref_id: tag[1], relay_id:relay_id, key: key))
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
			
			var pubkey = self.pubkey
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
	static func == (lhs:nostr.Event, rhs:nostr.Event) -> Bool {
		return lhs.uid == rhs.uid
	}
}

extension nostr.Event:Hashable {
	func hash(into hasher:inout Hasher) {
		hasher.combine(uid)
	}
}

extension nostr.Event:Identifiable {
	var id:String {
		return self.uid
	}
}

extension nostr.Event {
	/// The result of validating an event.
	func commitment() throws -> Data {
		let encoder = JSONEncoder()
		let tagsString = String(data:try encoder.encode(self.tags), encoding:.utf8)!
		let buildContentString = try encoder.encode(self.content)
		let contentString = String(data:buildContentString, encoding:.utf8)!
		let commit = "[0,\"\(self.pubkey)\",\(self.created.timeIntervalSince1970),\(self.kind.rawValue),\(tagsString),\(contentString)]"
		return Data(commit.utf8)
	}
	func validate() throws -> ValidationResult {
		let raw_id = sha256(try self.commitment())
		let id = hex_encode(raw_id)
		if id != self.uid {
			return .bad_id
		}
		guard var sig64 = hex_decode(self.sig) else {
			return .bad_sig
		}
		guard var ev_pubkey = hex_decode(self.pubkey) else {
			return .bad_sig
		}
		let ctx = try secp256k1.Context.create()
		var xonly_pubkey = secp256k1_xonly_pubkey.init()
		var ok = secp256k1_xonly_pubkey_parse(ctx, &xonly_pubkey, &ev_pubkey) != 0
		if !ok {
			return .bad_sig
		}
		var raw_id_bytes = raw_id.bytes

		ok = secp256k1_schnorrsig_verify(ctx, &sig64, &raw_id_bytes, raw_id.count, &xonly_pubkey) > 0
		return ok ? .ok : .bad_sig
	}
	func firstEventTag() -> String? {
		for tag in tags {
			if tag.kind == .event {
				return tag.info[0]
			}
		}
		return nil
	}
	func lastEventTag() -> String? {
		for tag in tags.reversed() {
			if tag.kind == .event {
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
	func blocks(_ privkey:String?) -> [Block] {
		return parse_mentions(content:content, tags:self.tags)
	}
	
	func getContent(privkey:String?) -> String {
		if kind == .dm {
			return decrypted(privkey:privkey) ?? "*failed*"
		}
		return content
	}
}

extension KeyPair {
	static func getSharedSecret(pubkey:String, privkey:String) throws -> [UInt8]? {
		let privkey_bytes = try privkey.bytes
		var pk_bytes = try pubkey.bytes
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
	guard let shared_sec = try? KeyPair.getSharedSecret(pubkey:pubkey, privkey: privkey) else {
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
	
	var note = decrypt_note(our_privkey: our_privkey, their_pubkey: zapreq.pubkey, enc_note: enc_note, encoding: .bech32)
	
	// check to see if the private note was from us
	if note == nil {
		guard let our_private_keypair = generate_private_keypair(our_privkey: our_privkey, id: target.id, created_at: Int64(zapreq.created.timeIntervalSince1970)) else{
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
		guard try zapreq.validate() == .ok else {
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
	} catch {
		print("decode_data failed for \(T.self): \(error)")
	}

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
	let blocks = ev.blocks(privkey).filter { block in
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
