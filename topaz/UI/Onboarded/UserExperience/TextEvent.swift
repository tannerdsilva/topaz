//
//  File.swift
//  topaz
//
//  Created by Tanner Silva on 3/9/23.
//

import SwiftUI

extension nostr.Event {
	struct ViewOptions: OptionSet {
		let rawValue: UInt8
		static let no_action_bar = ViewOptions(rawValue: 1 << 0)
		static let no_replying_to = ViewOptions(rawValue: 1 << 1)
		static let no_images = ViewOptions(rawValue: 1 << 2)
	}
}

struct TextEvent: View {
	let ue:UE
	let event:nostr.Event
	let pubkey:String
	let options:nostr.Event.ViewOptions
	
	var has_action_bar: Bool {
		!options.contains(.no_action_bar)
	}
	
	var body: some View {
		HStack(alignment: .top) {
			let profile = ue.lookup(id: pubkey)
		
			let is_anon = event_is_anonymous(ev: event)
			VStack {
//				MaybeAnonPfpView(state: damus, is_anon: is_anon, pubkey: pubkey)
				Text("TODO: Maybe anon view?")
				Spacer()
			}

			VStack(alignment: .leading) {
				HStack(alignment: .center) {
					let pk = is_anon ? "anon" : pubkey
					EventProfileName(pubkey: pk, profile: profile, ue:ue, show_friend_confirmed: true, size: .normal)
					
					Text(verbatim: "\(format_relative_time(event.created_at))")
						.foregroundColor(.gray)
					
					Spacer()
				}
				
				EventBody(ue:ue, event: event, size: .normal)
				
				if let mention = first_eref_mention(ev: event, privkey: damus.keypair.privkey) {
					BuilderEventView(damus: damus, event_id: mention.ref.id)
				}
				
				if has_action_bar {
					Rectangle().frame(height: 2).opacity(0)
					
					EventActionBar(damus_state: damus, event: event)
						.padding([.top], 4)
				}
			}
			.padding([.leading], 2)
		}
		.contentShape(Rectangle())
		.background(event_validity_color(event.validity))
		.id(event.id)
		.frame(maxWidth: .infinity, minHeight: PFP_SIZE)
		.padding([.bottom], 2)
		.event_context_menu(event, keypair: damus.keypair, target_pubkey: pubkey, bookmarks: damus.bookmarks)
	}
}

struct TextEvent_Previews: PreviewProvider {
	static var previews: some View {
		TextEvent(damus: test_damus_state(), event: test_event, pubkey: "pk", options: [])
	}
}

func event_has_tag(ev:nostr.Event, tag: String) -> Bool {
	for t in ev.tags {
		if t.count >= 1 && t[0] == tag {
			return true
		}
	}
	
	return false
}


func event_is_anonymous(ev:nostr.Event) -> Bool {
	return ev.kind == .zap_request && event_has_tag(ev: ev, tag: "anon")
}
