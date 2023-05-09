//
//  URI.swift
//  topaz
//
//  Created by Tanner Silva on 5/8/23.
//

import Foundation

extension nostr {
	struct URI {
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
			
		}
	}
}
