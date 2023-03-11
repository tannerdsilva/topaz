//
//  Reposted.swift
//  topaz
//
//  Created by Tanner Silva on 3/9/23.
//

import SwiftUI

struct Reposted: View {
	let ue:UE
	let pubkey: String
	let profile:nostr.Profile?
	
	var body: some View {
		HStack(alignment: .center) {
			Image(systemName:"arrow.2.squarepath")
				.font(.footnote)
				.foregroundColor(Color.gray)
			ProfileName(pubkey: pubkey, profile: profile, ue:ue, show_friend_confirmed: true, show_nip5_domain: false)
					.foregroundColor(Color.gray)
			Text("Reposted", comment: "Text indicating that the post was reposted (i.e. re-shared).")
				.font(.footnote)
				.foregroundColor(Color.gray)
		}
	}
}

struct Reposted_Previews: PreviewProvider {
	static var previews: some View {
		Reposted(ue:try! UE(keypair:Topaz.tester_account), pubkey:"foo", profile:nostr.Profile.makeTestProfile())
	}
}
