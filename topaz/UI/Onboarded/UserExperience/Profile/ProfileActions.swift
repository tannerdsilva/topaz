//
//  ProfileActions.swift
//  topaz
//
//  Created by Tanner Silva on 4/20/23.
//

import Foundation
import SwiftUI

extension UI.Profile {
	struct Actions {
		struct Configuration: OptionSet {
			let rawValue: Int
			static let dmButton = Configuration(rawValue: 1 << 0)
			static let sendTextNoteButton = Configuration(rawValue: 1 << 1)
			static let shareButton = Configuration(rawValue: 1 << 2)
			static let badgeButton = Configuration(rawValue: 1 << 3)
		}
		struct BadgeButton: View {
			let dbux:DBUX
			let pubkey:nostr.Key
			let profile:nostr.Profile?
			let sheetActions:UI.Profile.Actions.Configuration
			@Binding var showModal:Bool
			init(dbux: DBUX, pubkey: nostr.Key, profile: nostr.Profile?, sheetActions: UI.Profile.Actions.Configuration, showModal: Binding<Bool>) {
				self.dbux = dbux
				self.pubkey = pubkey
				self.profile = profile
				var actions = sheetActions
				actions.remove(.badgeButton)
				self.sheetActions = actions
				self._showModal = showModal
			}
			var body: some View {
				Button(action:{
					showModal = true
				}) {
					Image(systemName: "wallet.pass")
						.font(.title2)
				}
				.foregroundColor(Color.blue)
				.sheet(isPresented: $showModal, onDismiss: { showModal = false }) {
					UI.Profile.BadgeScreen(dbux:dbux, publicKey: pubkey, profile: profile ?? nostr.Profile(), configuration:sheetActions)
				}
			}
		}
		struct DirectMessageButton: View {
			let action: () -> Void

			var body: some View {
				Button(action: action) {
					Image(systemName: "envelope")
						.font(.title2)
						.foregroundColor(.blue)
				}
			}
		}
		struct SendTextNoteButton: View {
			let action: () -> Void

			var body: some View {
				Button(action: action) {
					Image(systemName: "arrowshape.turn.up.backward")
						.font(.title2)
						.foregroundColor(.blue)
				}
				.offset(y: -0.5) // Offset Reply Button
			}
		}
		struct ShareButton: View {
			let action: () -> Void

			var body: some View {
				Button(action: action) {
					Image(systemName: "square.and.arrow.up")
						.font(.title2)
						.foregroundColor(.blue)
				}
				.offset(y: -1) // Offset Share Button
			}
		}

	}
}
