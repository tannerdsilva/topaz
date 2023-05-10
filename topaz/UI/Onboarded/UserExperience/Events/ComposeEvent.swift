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
		@State private var attachMedia = false
		
		var ImageButton: some View {
			Button(action: {
				attachMedia = true
			}, label: {
				Image(systemName: "photo")
					.padding(6)
			})
		}
		
		var CameraButton: some View {
			Button(action: {
				attachMedia = true
			}, label: {
				Image(systemName: "camera")
					.padding(6)
			})
		}
		
		var body: some View {
			VStack {
				HStack {
					Button(action: {
						isShowingSheet.toggle()
					}) {
						Image(systemName: "xmark")
							.foregroundColor(.primary)
					}
					.padding(.leading, 16)
					.padding(.vertical, 12)
					Spacer()
					if (self.postContent.count > 0) {
						SendButton {
							do {
								try dbux.sendTextNoteContentToAllRelays(postContent)
								isShowingSheet.toggle()
							} catch {}
						}
						.padding(.trailing, 16)
						.padding(.vertical, 12)
					}
				}
				
				HStack(alignment:.top) {
					VStack {
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
						
						Spacer()
						
						ImageButton.padding(.bottom, 15)
						CameraButton
					}
					.padding(.leading)
					
					Divider()
						.padding(.horizontal)
					
					VStack {
						TextEditor(text: $postContent)
							.padding(.horizontal, 8)
					}
					.padding(.trailing)
				}
				.sheet(isPresented: $attachMedia) {
//					ImagePicker(sourceType: .photoLibrary, pubkey: dbux.keypair.pubkey) { img in
//						// self.mediaToUpload = .image(img)
//					}
				}
				.padding(.bottom)
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
