//
//  Filter.swift
//  topaz
//
//  Created by Tanner Silva on 3/7/23.
//

import Foundation

extension nostr {
	struct Filter:Codable {
		private enum CodingKeys:String, CodingKey {
			case ids
			case kinds
			case referenced_ids = "#e"
			case pubkeys = "#p"
			case hashtag = "#t"
			case parameter = "#d"
			case since
			case until
			case authors
			case limit
		}

		var ids:Set<String>?
		var kinds:Set<nostr.Event.Kind>?
		var referenced_ids:Set<String>?
		var pubkeys:Set<nostr.Key>?
		var since:Date?
		var until:Date?
		var limit:UInt32?

		/// The public keys of the authors of the messages to be returned.
		var authors:Set<nostr.Key>?
		var hashtag:Set<String>?
		var parameter:Set<String>?

		init(ids:Set<String>? = nil, kinds:Set<nostr.Event.Kind>? = nil, referenced_ids:Set<String>? = nil, pubkeys:Set<nostr.Key>? = nil, since:Date? = nil, until:Date? = nil, limit:UInt32? = nil, authors:Set<nostr.Key>? = nil, hashtag:Set<String>? = nil, parameter:Set<String>? = nil) {
			self.ids = ids
			self.kinds = kinds
			self.referenced_ids = referenced_ids
			self.pubkeys = pubkeys
			self.since = since
			self.until = until
			self.limit = limit
			self.authors = authors
			self.hashtag = hashtag
			self.parameter = parameter
		}

		// initialize from a decoder
		init(from decoder:Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			ids = try container.decodeIfPresent(Set<String>.self, forKey: .ids)
			kinds = try container.decodeIfPresent(Set<nostr.Event.Kind>.self, forKey: .kinds)
			referenced_ids = try container.decodeIfPresent(Set<String>.self, forKey: .referenced_ids)
			pubkeys = try container.decodeIfPresent(Set<nostr.Key>.self, forKey: .pubkeys)
			if let sinceTI = try container.decodeIfPresent(Int.self, forKey: .since) {
				since = Date(timeIntervalSince1970:Double(sinceTI))
			} else {
				since = nil
			}
			if let untilTI = try container.decodeIfPresent(Int.self, forKey: .until) {
				until = Date(timeIntervalSince1970:Double(untilTI))
			} else {
				until = nil
			}
			limit = try container.decodeIfPresent(UInt32.self, forKey: .limit)
			authors = try container.decodeIfPresent(Set<nostr.Key>.self, forKey: .authors)
			hashtag = try container.decodeIfPresent(Set<String>.self, forKey: .hashtag)
			parameter = try container.decodeIfPresent(Set<String>.self, forKey: .parameter)
		}
		
		// encode
		func encode(to encoder:Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encodeIfPresent(ids, forKey: .ids)
			try container.encodeIfPresent(kinds, forKey: .kinds)
			try container.encodeIfPresent(referenced_ids, forKey: .referenced_ids)
			try container.encodeIfPresent(pubkeys, forKey: .pubkeys)
			if let hasSince = since {
				try container.encodeIfPresent(Int(hasSince.timeIntervalSince1970), forKey: .since)
			}
			if let hasUntil = until {
				try container.encodeIfPresent(Int(hasUntil.timeIntervalSince1970), forKey: .until)
			}
			try container.encodeIfPresent(limit, forKey: .limit)
			try container.encodeIfPresent(authors, forKey: .authors)
			try container.encodeIfPresent(hashtag, forKey: .hashtag)
			try container.encodeIfPresent(parameter, forKey: .parameter)
		}
	}
}

extension nostr.Filter {
	public static func makeHashtagFilter(_ hashtag:String) -> nostr.Filter {
		return nostr.Filter(hashtag: [hashtag])
	}

	public static func makeAuthorFilter(_ author:nostr.Key) -> nostr.Filter {
		return nostr.Filter(authors: [author])
	}
	public static func makeSinceFilter(_ since:Date) -> nostr.Filter {
		return nostr.Filter(since: since)
	}

	public static func makeUntilFilter(_ until:Date) -> nostr.Filter {
		return nostr.Filter(until: until)
	}
}

extension nostr.Filter: Equatable {
	static func == (lhs:nostr.Filter, rhs:nostr.Filter) -> Bool {
		return lhs.ids == rhs.ids &&
			lhs.kinds == rhs.kinds &&
			lhs.referenced_ids == rhs.referenced_ids &&
			lhs.pubkeys == rhs.pubkeys &&
			lhs.since == rhs.since &&
			lhs.until == rhs.until &&
			lhs.limit == rhs.limit &&
			lhs.authors == rhs.authors &&
			lhs.hashtag == rhs.hashtag &&
			lhs.parameter == rhs.parameter
	}
}

extension nostr.Filter: Hashable {
	func hash(into hasher: inout Hasher) {
		hasher.combine(ids)
		hasher.combine(kinds)
		hasher.combine(referenced_ids)
		hasher.combine(pubkeys)
		hasher.combine(since)
		hasher.combine(until)
		hasher.combine(limit)
		hasher.combine(authors)
		hasher.combine(hashtag)
		hasher.combine(parameter)
	}
}
