//
//  Event.swift
//  topaz
//
//  Created by Tanner Silva on 3/7/23.
//

import Foundation
import QuickLMDB

extension nostr {
	struct Event:Codable {
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
		}
		enum Block {
			case text(String)
			case mention(Mention)
			case hashtag(String)
			case url(URL)
			case invoice(Invoice)
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
	}
}

extension nostr.Event {
	var isTextlike:Bool {
		get {
			return kind == .text_note || kind == .chat
		}
	}
}

extension nostr.Event {
	struct Mention {
		let pubkey:String
		let username:String
	}
}
