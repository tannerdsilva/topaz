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
			VStack {
				HStack() {
					VStack(alignment: .center) {
						Button("Cancel", action: {
							isShowingSheet.toggle()
						})
					}
					Spacer()
					VStack(alignment: .center) {
						if (self.postContent.count > 0) {
							SendButton {
								do {
									try dbux.sendTextNoteContentToAllRelays(postContent)
									isShowingSheet.toggle()
								} catch {}
							}.border(.pink)
						}
					}.padding().frame(height:45).border(.purple)
				}
				HStack(alignment:.top) {
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
					VStack {
						TextEditor(text: $postContent)
							.padding()
							.padding(.horizontal)
					}.border(.cyan)
				}.border(.yellow)
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
