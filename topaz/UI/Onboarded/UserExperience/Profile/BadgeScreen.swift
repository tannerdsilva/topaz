//
//  MetadataScreen.swift
//  topaz
//
//  Created by Tanner Silva on 4/18/23.
//

import Foundation
import SwiftUI

extension UI.Profile {
	struct WalletsInfoView:View {
		let profile:nostr.Profile
		var body:some View {
			if profile.wallets?.xmr != nil {
				UI.Profile.WalletAddressView(wallet:profile.wallets!.xmr!, config: .xmr)
			}
			if profile.wallets?.btc != nil {
				UI.Profile.WalletAddressView(wallet:profile.wallets!.btc!, config: .btc)
			}
			if profile.wallets?.ltc != nil {
				UI.Profile.WalletAddressView(wallet:profile.wallets!.ltc!, config: .ltc)
			}
		}
	}
	
	struct BadgeScreen: View {
		let dbux:DBUX
		let followingYou:Bool = true
		let publicKey:nostr.Key
		let profile:nostr.Profile
		let configuration:UI.Profile.Actions.Configuration
		
		var body: some View {
			VStack {
				HStack {
					if (followingYou) == true {
						FollowsYouView().padding(.top, 7)
					}
					Spacer()
					CommonRelaysView(relays: 5).padding(.top, 7)
					
				}.padding(.horizontal, 13)
				List {
					UI.Profile.ListItem(dbux:dbux, profile:self.profile, publicKey:self.publicKey, buttonConfiguration:configuration).frame(height: 60)
					UI.Profile.PublicKeyView(key:publicKey)
					WalletsInfoView(profile:profile)
					
					if let about = profile.about {
						Section(header: Text("About")) {
							Text(about)
						}
					}
					
					
					if let website = profile.website_url {
						Section(header: Text("Website")) {
							Link("Visit Website", destination: website)
						}
					}

					if let nip05 = profile.nip05 {
						Section(header: Text("NIP05 Verification Address")) {
							Text(nip05)
						}
					}
				}
				.listStyle(GroupedListStyle())
				.background(Color(.systemGroupedBackground))
				.edgesIgnoringSafeArea(.top)
				.navigationTitle("User Profile")
				Spacer()
			}
		}
	}
}
