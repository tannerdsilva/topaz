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

		var ids:[String]?
		var kinds:[String]?
		var referenced_ids:[String]?
		var pubkeys:[String]?
		var since:Date?
		var until:Date?
		var limit:UInt32?
		var authors:[String]?
		var hashtag:[String]?
		var parameter:[String]?

		init(ids:[String]? = nil, kinds:[String]? = nil, referenced_ids:[String]? = nil, pubkeys:[String]? = nil, since:Date? = nil, until:Date? = nil, limit:UInt32? = nil, authors:[String]? = nil, hashtag:[String]? = nil, parameter:[String]? = nil) {
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
			ids = try container.decodeIfPresent([String].self, forKey: .ids)
			kinds = try container.decodeIfPresent([String].self, forKey: .kinds)
			referenced_ids = try container.decodeIfPresent([String].self, forKey: .referenced_ids)
			pubkeys = try container.decodeIfPresent([String].self, forKey: .pubkeys)
			since = try container.decodeIfPresent(Date.self, forKey: .since)
			until = try container.decodeIfPresent(Date.self, forKey: .until)
			limit = try container.decodeIfPresent(UInt32.self, forKey: .limit)
			authors = try container.decodeIfPresent([String].self, forKey: .authors)
			hashtag = try container.decodeIfPresent([String].self, forKey: .hashtag)
			parameter = try container.decodeIfPresent([String].self, forKey: .parameter)
		}
		
		// encode
		func encode(to encoder:Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encodeIfPresent(ids, forKey: .ids)
			try container.encodeIfPresent(kinds, forKey: .kinds)
			try container.encodeIfPresent(referenced_ids, forKey: .referenced_ids)
			try container.encodeIfPresent(pubkeys, forKey: .pubkeys)
			try container.encodeIfPresent(since, forKey: .since)
			try container.encodeIfPresent(until, forKey: .until)
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

	public static func makeAuthorFilter(_ author:String) -> nostr.Filter {
		return nostr.Filter(authors: [author])
	}

	public static func makeKindFilter(_ kind:String) -> nostr.Filter {
		return nostr.Filter(kinds: [kind])
	}

	public static func makeSinceFilter(_ since:Date) -> nostr.Filter {
		return nostr.Filter(since: since)
	}

	public static func makeUntilFilter(_ until:Date) -> nostr.Filter {
		return nostr.Filter(until: until)
	}
}
