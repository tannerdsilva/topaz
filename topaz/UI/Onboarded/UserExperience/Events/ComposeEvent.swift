//
//  ComposeEvent.swift
//  topaz
//
//  Created by Tanner Silva on 4/19/23.
//

import Foundation
import SwiftUI

extension UI.Events {
	struct NewPostView: View {
		let dbux: DBUX
		let profile: nostr.Profile?
		let publicKey: nostr.Key
		@Binding var isShowingSheet: Bool
		@State private var postContent = ""

		var body: some View {
			NavigationView {
				VStack {
					HStack {
						// Profile picture
						if let profilePicture = profile?.picture, let url = URL(string: profilePicture) {
							CachedAsyncImage(url: url, imageCache: dbux.imageCache) { image in
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
						Text("Compose a New Post")
							.font(.title)
							.padding()
					}
					.padding(.top)

					TextEditor(text: $postContent)
						.padding()
						.overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray, lineWidth: 1))
						.padding(.horizontal)

					Spacer()
				}
				.navigationBarItems(trailing: SendButton {
					do {
						try dbux.sendTextNoteContentToAllRelays(postContent)
						isShowingSheet.toggle()
					} catch {}
				})
				.background(Color(UIColor.systemGroupedBackground))
				.edgesIgnoringSafeArea(.bottom)
			}
		}
	}
	
	struct SendButton: View {
		let action: () -> Void
		
		var body: some View {
			Button(action: action) {
				Text("Send")
					.foregroundColor(Color.blue)
			}
		}
	}
}
