//
//  ProfileMetadataEditView.swift
//  topaz
//
//  Created by Tanner Silva on 4/20/23.
//

import Foundation
import SwiftUI

extension UI.Profile {
	struct ProfileMetadataEditView: View {
		let dbux:DBUX
		@State private var profile:nostr.Profile
		@State private var pubkey:String
		@Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
		@State private var showWalletEditor: Bool = false
		
		@FocusState private var focusedField: Field?
		private enum Field: Hashable {
			case name, displayName, about, profilePicture, profileBanner, website, lnurlPay
		}
		
		init(dbux:DBUX, profile:nostr.Profile, pubkey:String) {
			self.dbux = dbux
			self._profile = State(initialValue: profile)
			self._pubkey = State(initialValue: pubkey)
		}
		
		var body: some View {
			List {
				Section(header: Text("Profile Information")) {
					TextField("Name", text: Binding(get: { profile.name ?? "" }, set: { profile.name = $0.isEmpty ? nil : $0 }))
						.focused($focusedField, equals: .name)
						.submitLabel(.next)
					
					TextField("Display Name", text: Binding(get: { profile.display_name ?? "" }, set: { profile.display_name = $0.isEmpty ? nil : $0 }))
						.focused($focusedField, equals: .displayName)
						.submitLabel(.next)
					
					TextEditor(text: Binding(get: { profile.about ?? "" }, set: { profile.about = $0.isEmpty ? nil : $0 }))
						.focused($focusedField, equals: .about)
						.submitLabel(.next)
						.frame(height: 100) // Adjust the height as needed
				}
				
//				Section(header: Text("Wallets")) {
					Section(header: Text("Wallets")) {
						TextField("Bitcoin (BTC) Address", text: Binding(get: { profile.wallets?.btc ?? "" }, set: { newValue in
							if !newValue.isEmpty {
								if profile.wallets == nil {
									profile.wallets = nostr.Profile.Wallets()
								}
								profile.wallets?.btc = newValue
							} else {
								profile.wallets?.btc = nil
							}
						}))
						
						TextField("Litecoin (LTC) Address", text: Binding(get: { profile.wallets?.ltc ?? "" }, set: { newValue in
							if !newValue.isEmpty {
								if profile.wallets == nil {
									profile.wallets = nostr.Profile.Wallets()
								}
								profile.wallets?.ltc = newValue
							} else {
								profile.wallets?.ltc = nil
							}
						}))
						
						TextField("Monero (XMR) Address", text: Binding(get: { profile.wallets?.xmr ?? "" }, set: { newValue in
							if !newValue.isEmpty {
								if profile.wallets == nil {
									profile.wallets = nostr.Profile.Wallets()
								}
								profile.wallets?.xmr = newValue
							} else {
								profile.wallets?.xmr = nil
							}
						}))
					}
//				}
				
				Section(header: Text("Profile Media")) {
					TextField("Profile Picture URL", text: Binding(get: { profile.picture ?? "" }, set: { profile.picture = $0.isEmpty ? nil : $0 }))
						.focused($focusedField, equals: .profilePicture)
						.submitLabel(.next)
					
					TextField("Profile Banner URL", text: Binding(get: { profile.banner ?? "" }, set: { profile.banner = $0.isEmpty ? nil : $0 }))
						.focused($focusedField, equals: .profileBanner)
						.submitLabel(.next)
				}
		
				Section(header: Text("Website & Payment")) {
					TextField("Website URL", text: Binding(get: { profile.website ?? "" }, set: { profile.website = $0.isEmpty ? nil : $0 }))
						.focused($focusedField, equals: .website)
						.submitLabel(.next)
					
					TextField("LNURL-Pay Address", text: Binding(get: { profile.lnurl ?? "" }, set: { profile.lud16 = $0.isEmpty ? nil : $0 }))
						.focused($focusedField, equals: .lnurlPay)
						.submitLabel(.done)
				}
				
				
			}
			.listStyle(GroupedListStyle())
			.navigationTitle("Edit Profile")
			.toolbar {
				ToolbarItem(placement: .navigationBarTrailing) {
					Button("Save", action: {
						// Save the data and pop the view
						self.saveProfileData()
						self.presentationMode.wrappedValue.dismiss()
					})
				}
			}
			.onTapGesture {
				focusedField = nil
			}
		}
		
		@MainActor func saveProfileData() {
//			Task.detached(operation: {
				try? dbux.updateProfile(self.profile)
//			})
		}
	}
}
