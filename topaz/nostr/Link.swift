//
//  Link.swift
//  topaz
//
//  Created by Tanner Silva on 5/5/23.
//

import Foundation

extension nostr {
	enum Link:Equatable {
		case ref(nostr.ReferenceID)
		case filter(nostr.Filter)
	}
}
