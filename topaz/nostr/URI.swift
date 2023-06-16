//
//  URI.swift
//  topaz
//
//  Created by Tanner Silva on 5/8/23.
//

import Foundation

extension nostr {
	struct URI {
		enum Error:Swift.Error {
			case invalidURIString(String)
		}
		static func decode(_ s:String) throws -> nostr.Link {
			var uri = s.replacingOccurrences(of: "nostr://", with: "")
			uri = uri.replacingOccurrences(of: "nostr:", with: "")
			
			uri = uri.replacingOccurrences(of: "topaz://", with: "")
			uri = uri.replacingOccurrences(of: "topaz:", with: "")
			
			let parts = uri.split(separator: ":").reduce(into: Array<String>()) { acc, str in
				guard let decoded = str.removingPercentEncoding else {
					return
				}
				acc.append(decoded)
				return
			}
			// if hashtag
			if parts.count >= 2 && parts[0] == "t" {
				return .filter(nostr.Filter(hashtag:[parts[1]]))
			}
			// if reference
			if let asRef = ReferenceID(parts) {
				return .ref(asRef)
			}
			// if bech32 encoded
			switch try Bech32.Object.parse(parts[0]) {
			case .npub(let pubkey):
				return .ref(nostr.ReferenceID(ref_id: pubkey, relay_id: nil, key: "p"))
			case .note(let id):
				return .ref(nostr.ReferenceID(ref_id: id, relay_id: nil, key: "e"))
			default:
				throw Error.invalidURIString(s)
			}
		}
	}
}
