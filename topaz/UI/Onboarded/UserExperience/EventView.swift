//
//  EventView.swift
//  topaz
//
//  Created by Tanner Silva on 3/9/23.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

func eventviewsize_to_font(_ size: EventView.Kind) -> Font {
	switch size {
	case .small:
		return .body
	case .normal:
		return .body
	case .selected:
		return .custom("selected", size: 21.0)
	}
}

struct EventView: View {
	enum Kind {
		case small
		case normal
		case selected
	}
	let event:nostr.Event
	let options:nostr.Event.ViewOptions
	let ue:UE
	let pubkey: String

	@EnvironmentObject var action_bar: ActionBarModel

	init(ue:UE, event:nostr.Event, options:nostr.Event.ViewOptions) {
		self.event = event
		self.options = options
		self.ue = ue
		self.pubkey = event.pubkey
	}

	init(ue:UE, event:nostr.Event) {
		self.event = event
		self.options = []
		self.ue = ue
		self.pubkey = event.pubkey
	}

	init(ue:UE, event:nostr.Event, pubkey:String) {
		self.event = event
		self.options = [.no_action_bar]
		self.ue = ue
		self.pubkey = pubkey
	}

	var body: some View {
		VStack {
			TextEvent(ue:ue, event: event, pubkey: pubkey, options: options)
					.padding([.top], 6)
		}
	}
}

// blame the porn bots for this code
func should_show_images(ue:UE, ev:nostr.Event, our_pubkey: String, booster_pubkey: String? = nil) -> Bool {
	if ev.pubkey == our_pubkey {
		return true
	}
	do {
		let openTrans = try ue.transact(readOnly:true)
		defer {
			try? openTrans.commit()
		}
		if try ue.contactsDB.isInFriendosphere(pubkey:ev.pubkey, tx: openTrans) {
			return true
		}
		if booster_pubkey != nil {
			if try ue.contactsDB.isInFriendosphere(pubkey:booster_pubkey!, tx:openTrans) {
				return true
			}
		}
		return false
	} catch _ {
		return false
	}
}

func event_validity_color(_ validation:nostr.Event.ValidationResult) -> some View {
	Group {
		switch validation {
		case .ok:
			EmptyView()
		case .bad_id:
			Color.orange.opacity(0.4)
		case .bad_sig:
			Color.red.opacity(0.4)
		}
	}
}

extension View {
	func pubkey_context_menu(bech32_pubkey: String) -> some View {
		return self.contextMenu {
//			Button {
//				UIPasteboard.general.string.setValue(bech32_pubkey, forPasteboardType: UTType.plainText.identifier)
//			} label: {
//				Label(NSLocalizedString("Copy Account ID", comment: "Context menu option for copying the ID of the account that created the note."), systemImage: "doc.on.doc")
//			}
		}
	}
	
//	func event_context_menu(_ event:nostr.Event, keypair:KeyPair, target_pubkey: String, bookmarks: BookmarksManager) -> some View {
//		return self.contextMenu {
//			EventMenuContext(event: event, keypair: keypair, target_pubkey: target_pubkey, bookmarks: bookmarks)
//		}
//
//	}
}

func format_date(_ created_at: Int64) -> String {
	let date = Date(timeIntervalSince1970: TimeInterval(created_at))
	let dateFormatter = DateFormatter()
	dateFormatter.timeStyle = .short
	dateFormatter.dateStyle = .short
	return dateFormatter.string(from: date)
}

func make_actionbar_model(ev:String, ue:UE) -> ActionBarModel {
	let our_like:nostr.Event? = nil
	let our_boost:nostr.Event? = nil
	let our_zap:Zap? = nil

	return ActionBarModel(likes: 0,
						  boosts: 0,
						  zaps: 0,
						  zap_total: 0,
						  our_like: our_like,
						  our_boost: our_boost,
						  our_zap:our_zap
	)
}


struct EventView_Previews: PreviewProvider {
	static var previews: some View {
		VStack {
			EventView(ue:try! UE(keypair:Topaz.tester_account), event: test_event )
		}
		.padding()
	}
}

let test_event = nostr.Event.createTestPost()
