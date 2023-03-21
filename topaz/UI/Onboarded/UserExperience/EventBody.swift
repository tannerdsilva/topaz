//
//  EventBody.swift
//  topaz
//
//  Created by Tanner Silva on 3/9/23.


import SwiftUI


struct EventBody:View {
	let ue:UE
	let event:nostr.Event
	let size:EventView.Kind
	let should_show_img: Bool
	
	init(ue:UE, event:nostr.Event, size:EventView.Kind, should_show_img: Bool? = nil) {
		self.ue = ue
		self.event = event
		self.size = size
		self.should_show_img = true
	}
	
	var content: String {
		event.getContent(privkey:ue.keypair.privkey)
	}
	
	var body: some View {
		if event_is_reply(event, privkey: ue.keypair.privkey) {
//			ReplyDescription(ue:ue, event: event)
		}
		Text("Note content view")
//		NoteContentView(ue:ue, event: event, show_images: should_show_img, size: size, artifacts: .just_content(content), truncate: true).frame(maxWidth: .infinity, alignment: .leading)
	}
}
