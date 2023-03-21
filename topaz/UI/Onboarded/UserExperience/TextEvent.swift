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
	
	func getProfileFromUE() -> nostr.Profile? {
		let profile:nostr.Profile?
		do {
			profile = try ue.profilesDB.getPublicKeys(publicKeys:Set([pubkey])).first!.value
		} catch _ {
			profile = nil
		}
		return profile
	}
	
	var body: some View {
		HStack(alignment: .top) {
			let profile = getProfileFromUE()
		
			let is_anon = event_is_anonymous(ev: event)
			VStack {
				Text("TODO: Maybe anon view?")
				Spacer()
			}

			VStack(alignment: .leading) {
				HStack(alignment: .center) {
					let pk = is_anon ? "anon" : pubkey
//					EventProfileName(pubkey: pk, profile:profile, ue:ue, show_friend_confirmed: true, size: .normal)
					
					Text(verbatim:"\(event.created.relativeShortTimeString())")
						.foregroundColor(.gray)
					
					Spacer()
				}
				
				EventBody(ue:ue, event: event, size:.normal)
				
				if let mention = first_eref_mention(ev: event, privkey:ue.keypair.privkey) {
					Text("Builder event view?")
//					BuilderEventView(ue:ue, event_id: mention.ref.id)
				}
				
				if has_action_bar {
					Rectangle().frame(height: 2).opacity(0)
					
					Text("Event Action Bar?")
//					EventActionBar(ue:ue, event: event)
//						.padding([.top], 4)
				}
			}
			.padding([.leading], 2)
		}
		.contentShape(Rectangle())
		.background(event_validity_color((try? event.validate()) ?? .bad_sig))
		.id(event.id)
		.frame(maxWidth: .infinity, minHeight: 52)
		.padding([.bottom], 2)
//		.event_context_menu(event, keypair:ue.keypair, target_pubkey: pubkey, bookmarks: damus.bookmarks)
		
		Text("event context menu?")
	}
}

struct TextEvent_Previews: PreviewProvider {
	static var previews: some View {
		TextEvent(ue:try! UE(keypair:Topaz.tester_account), event:test_event, pubkey:"pk", options: [])
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
