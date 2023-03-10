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
	/// a reference to another event
	struct Reference:Hashable, Equatable, Identifiable {
		let ref_id:String
		let relay_id:String?
		let key:String

		var id:String {
			return ref_id
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
		}

		struct Tag:Codable {
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
		var decrypted_content: String? = nil
		func decrypted(privkey: String?) -> String? {
			if let decrypted_content = decrypted_content {
				return decrypted_content
			}

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
			self.decrypted_content = dec

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
}

extension KeyPair {
	func getSharedSecret() throws -> [UInt8]? {
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

func decrypt_private_zap(our_privkey: String, zapreq:nostr.Event, target:Zap.Target) -> nostr.Event? {
	guard let anon_tag = zapreq.tags.first(where: { t in t.count >= 2 && t[0] == "anon" }) else {
		return nil
	}
	
	let enc_note = anon_tag[1]
	
	var note = decrypt_note(our_privkey: our_privkey, their_pubkey: zapreq.pubkey, enc_note: enc_note, encoding: .bech32)
	
	// check to see if the private note was from us
	if note == nil {
		guard let our_private_keypair = generate_private_keypair(our_privkey: our_privkey, id: target.id, created_at: zapreq.created_at) else{
			return nil
		}
		// use our private keypair and their pubkey to get the shared secret
		note = decrypt_note(our_privkey: our_private_keypair.privkey, their_pubkey: target.pubkey, enc_note: enc_note, encoding: .bech32)
	}
	
	guard let note else {
		return nil
	}
		
	guard note.kind == 9733 else {
		return nil
	}
	
	let zr_etag = zapreq.referenced_ids.first
	let note_etag = note.referenced_ids.first
	
	guard zr_etag == note_etag else {
		return nil
	}
	
	let zr_ptag = zapreq.referenced_pubkeys.first
	let note_ptag = note.referenced_pubkeys.first
	
	guard let zr_ptag, let note_ptag, zr_ptag == note_ptag else {
		return nil
	}
	
	guard validate_event(ev: note) == .ok else {
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

func decode_nostr_event_json(json: String) -> NostrEvent? {
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
