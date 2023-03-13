//
//  ProfileName.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

func get_friend_icon(ue:UE, pubkey: String, show_confirmed: Bool) -> String? {
	if !show_confirmed {
		return nil
	}
	do {
		let newTransaction = try ue.transact(readOnly:true)
		defer {
			try? newTransaction.commit()
		}
		if try ue.contactsDB.isFriend(pubkey:pubkey, tx:newTransaction) {
			return "person.fill.checkmark"
		}
		
		if try ue.contactsDB.isFriendOfFriend(pubkey:pubkey, tx:newTransaction) {
			return "person.fill.and.arrow.left.and.arrow.right"
		}
		return nil
	} catch _ {
		return nil
	}
}

struct ProfileName: View {
	let ue:UE
	let pubkey: String
	let profile:nostr.Profile?
	let prefix: String
	
	let show_friend_confirmed: Bool
	let show_nip5_domain: Bool
	
	@State var display_name: String?
	@State var nip05: NIP05?

	init(pubkey: String, profile:nostr.Profile?, ue:UE, show_friend_confirmed: Bool, show_nip5_domain: Bool = true) {
		self.pubkey = pubkey
		self.profile = profile
		self.prefix = ""
		self.show_friend_confirmed = show_friend_confirmed
		self.show_nip5_domain = show_nip5_domain
		self.ue = ue
	}
	
	init(pubkey: String, profile:nostr.Profile?, prefix: String, ue:UE, show_friend_confirmed: Bool, show_nip5_domain: Bool = true) {
		self.pubkey = pubkey
		self.profile = profile
		self.prefix = prefix
		self.ue = ue
		self.show_friend_confirmed = show_friend_confirmed
		self.show_nip5_domain = show_nip5_domain
	}
	
	var friend_icon: String? {
//		return get_friend_icon(contacts: damus_state.contacts, pubkey: pubkey, show_confirmed: show_friend_confirmed)
		return nil
	}
	
	var current_nip05: NIP05? {
		return nil
	}
	
	var nip05_color: Color {
		return Color.blue
	}
	
	var body: some View {
		HStack(spacing: 2) {
			Text(verbatim: "\(prefix)\(String(display_name ?? nostr.Profile.displayName(profile: profile, pubkey: pubkey)))")
				.font(.body)
				.fontWeight(prefix == "@" ? .none : .bold)
			if let nip05 = current_nip05 {
				Text("NIP Badge would go here")
			}
			if let friend = friend_icon, current_nip05 == nil {
				Image(systemName: friend)
					.foregroundColor(.gray)
			}
		}
	}
}

/// Profile Name used when displaying an event in the timeline
struct EventProfileName: View {
	let ue:UE
	let pubkey: String
	@State var profile:nostr.Profile?
	let prefix: String
	
	let show_friend_confirmed: Bool
	
	@State var display_name: String?
	@State var nip05: NIP05?
	
	let size:EventView.Kind
	
	init(pubkey: String, profile:nostr.Profile?, ue:UE, show_friend_confirmed: Bool, size: EventView.Kind = .normal) {
		self.ue = ue
		self.pubkey = pubkey
		self.profile = profile
		self.prefix = ""
		self.show_friend_confirmed = show_friend_confirmed
		self.size = size
	}
	
	init(pubkey: String, profile:nostr.Profile?, prefix: String, ue:UE, show_friend_confirmed: Bool, size:EventView.Kind = .normal) {
		self.ue = ue
		self.pubkey = pubkey
		self.profile = profile
		self.prefix = prefix
		self.show_friend_confirmed = show_friend_confirmed
		self.size = size
	}
	
	var friend_icon: String? {
		return get_friend_icon(ue:ue, pubkey: pubkey, show_confirmed: show_friend_confirmed)
	}
	
	var current_nip05: NIP05? {
		nil
	}
   
	var body: some View {
		HStack(spacing: 2) {
			if let real_name = profile?.display_name {
				Text(real_name)
					.font(.body.weight(.bold))
					.padding([.trailing], 2)
				
				Text(verbatim: "@\(display_name ?? nostr.Profile.displayName(profile: profile, pubkey: pubkey))")
					.foregroundColor(Color("DamusMediumGrey"))
					.font(eventviewsize_to_font(size))
			} else {
				Text(verbatim: "\(display_name ?? nostr.Profile.displayName(profile: profile, pubkey: pubkey))")
					.font(eventviewsize_to_font(size))
					.fontWeight(.bold)
			}
			
			if let nip05 = current_nip05 {
				Text("NIP BADGE GOES HERE")
//				NIP05Badge(nip05: nip05, pubkey: pubkey, contacts: damus_state.contacts, show_domain: false, clickable: false)
			}
			
			if let frend = friend_icon, current_nip05 == nil {
				Label("", systemImage: frend)
					.foregroundColor(.gray)
					.font(.footnote)
			}
		}
	}
}

