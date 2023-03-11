//
//  EventBody.swift
//  topaz
//
//  Created by Tanner Silva on 3/9/23.


import SwiftUI

struct EventBody:View {
	let ue:UE
	let event:nostr.Event
	let size:nostr.Event.ViewOptions
	let should_show_img: Bool
	
	init(ue:UE, event:nostr.Event, size:nostr.Event.ViewOptions, should_show_img: Bool? = nil) {
		self.ue = ue
		self.event = event
		self.size = size
		self.should_show_img = true
	}
	
	var content: String {
		event.getContent(privkey:ue.keypair.privkey)
	}
	
	var body: some View {
		event.ref
		if event_is_reply(event, privkey: ue.keypair.privkey) {
			ReplyDescription(event: event, profiles: damus_state.profiles)
		}

		NoteContentView(damus_state: damus_state, event: event, show_images: should_show_img, size: size, artifacts: .just_content(content), truncate: true)
			.frame(maxWidth: .infinity, alignment: .leading)
	}
}
