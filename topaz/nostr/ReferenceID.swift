//
//  ReferenceID.swift
//  topaz
//
//  Created by Tanner Silva on 3/7/23.
//

import Foundation

struct ReferenceID:Codable {
	let ref_id:String
	let relay_id:String
	let key:String
}

extension ReferenceID:Hashable {
	public func hash(into hasher:inout Hasher) {
		hasher.combine(ref_id)
		hasher.combine(relay_id)
		hasher.combine(key)
	}
}
