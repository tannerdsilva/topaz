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
		let dbux:DBUX
		@Binding var isShowingSheet: Bool
		@State private var postContent = ""
		
		var body: some View {
			NavigationView {
				VStack {
					Text("Compose a New Post")
						.font(.title)
						.padding()
					
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
