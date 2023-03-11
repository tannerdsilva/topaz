//
//  ReferenceID.swift
//  topaz
//
//  Created by Tanner Silva on 3/7/23.
//

import Foundation

extension ReferenceID:Hashable {
	public func hash(into hasher:inout Hasher) {
		hasher.combine(ref_id)
		hasher.combine(relay_id)
		hasher.combine(key)
	}
}
