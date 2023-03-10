//
//  NIP05.swift
//  topaz
//
//  Created by Tanner Silva on 3/9/23.
//

import Foundation

struct NIP05 {
	struct Response:Codable {
		let names:[String:String]
		let relays:[String:String]
	}
	let username:String
	let host:String
	
	static func parse(_ nip05:String) -> NIP05? {
		let parts = nip05.split(separator:"@")
		guard parts.count == 2 else {
			return nil
		}
		return NIP05(username:String(parts[0]), host:String(parts[1]))
	}
}
