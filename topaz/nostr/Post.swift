//
//  Post.swift
//  topaz
//
//  Created by Tanner Silva on 4/10/23.
//

import Foundation

extension nostr {
	struct Post {
		let kind:nostr.Event.Kind
		let content:String
		let references:[ReferenceID]
		
		init (content: String, references: [ReferenceID]) {
			self.content = content
			self.references = references
			self.kind = .text_note
		}
		
		init (content: String, references: [ReferenceID], kind:nostr.Event.Kind) {
			self.content = content
			self.references = references
			self.kind = kind
		}
	}
}
