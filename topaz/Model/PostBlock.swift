//
//  PostBlock.swift
//  topaz
//
//  Created by Tanner Silva on 3/10/23.
//

import Foundation

enum PostBlock {
	case text(String)
	case ref(nostr.Reference)
	case hashtag(String)
	
	var is_text: String? {
		if case .text(let txt) = self {
			return txt
		}
		return nil
	}
	
	var is_hashtag: String? {
		if case .hashtag(let ht) = self {
			return ht
		}
		return nil
	}
	
	var is_ref: nostr.Reference? {
		if case .ref(let ref) = self {
			return ref
		}
		return nil
	}
}

func parse_post_textblock(str: String, from: Int, to: Int) -> PostBlock {
	return .text(String(substring(str, start: from, end: to)))
}
