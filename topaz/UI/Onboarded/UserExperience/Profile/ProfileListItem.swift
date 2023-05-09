//
//  ProfileListItem.swift
//  topaz
//
//  Created by Tanner Silva on 4/20/23.
//

import Foundation
import SwiftUI

extension UI.Profile {
	struct ListItem: View {
		let dbux:DBUX
		let profile: nostr.Profile?
		let publicKey: nostr.Key
		let buttonConfiguration:UI.Profile.Actions.Configuration
		@State var showModal = false
		var body: some View {
			GeometryReader { geometry in
				VStack {
					Spacer()
					
					HStack {
						// Profile picture
						if let profilePicture = profile?.picture, let url = URL(string: profilePicture) {
							UI.Images.AssetPipeline.AsyncImage(url: url, actor:dbux.storedImageActor) { image in
								image
									.resizable()
									.aspectRatio(contentMode: .fill)
							} placeholder: {
								ProgressView()
							}
							.frame(width: 40, height: 40)
							.clipShape(Circle())
						} else {
							Image(systemName: "person.crop.circle.fill")
								.resizable()
								.frame(width: 40, height: 40)
								.foregroundColor(.gray)
						}
						
						// Profile info
						VStack(alignment: .leading, spacing: 4) {
							HStack(spacing: 4) {
								Text(nostr.Profile.displayName(profile: profile, pubkey: publicKey.description))
									.font(.headline)
								
								if profile?.nip05 != nil {
									Image(systemName: "checkmark.circle.fill")
										.foregroundColor(.blue)
										.font(.system(size: 16))
								}
							}
							
							if let displayName = profile?.display_name {
								Text(displayName)
									.font(.subheadline)
									.foregroundColor(.gray)
							}
						}
						
						Spacer()
						
						// Button Group
						HStack(spacing: 16) {
							// Direct Message Button
							if buttonConfiguration.contains(.dmButton) {
								UI.Profile.Actions.DirectMessageButton(action: {
									// Direct Message Action
								})
							}
							
							// Reply Button
							if buttonConfiguration.contains(.sendTextNoteButton) {
								UI.Profile.Actions.SendTextNoteButton(action: {
									// Reply Action
								})
							}
							
							// Share Button
							if buttonConfiguration.contains(.shareButton) {
								UI.Profile.Actions.ShareButton(action: {
									// Share Action
								})
							}
							
							// Badge Button
							if buttonConfiguration.contains(.badgeButton) {
								UI.Profile.Actions.BadgeButton(dbux:dbux, pubkey: publicKey, profile: profile, sheetActions:[.dmButton, .sendTextNoteButton, .shareButton], showModal: $showModal)
							}
						}
					}
					
					Spacer()
					
				}
			}
		}
	}
}
