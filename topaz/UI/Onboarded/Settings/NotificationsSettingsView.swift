//
//  NotificationsView.swift
//  topaz
//
//  Created by Tanner Silva on 4/28/23.
//

import Foundation
import SwiftUI

extension UI {
	struct NotificationsSettingsView: View {
		@State private var zaps = false
		@State private var mentions = false
		@State private var reposts = false
		@State private var likes = false
		@State private var onlyFromFollowed = false
		
		var body: some View {
			List {
				Toggle(isOn: $zaps) {
					Text("Zaps")
				}
				
				Toggle(isOn: $mentions) {
					Text("Mentions")
				}
				
				Toggle(isOn: $reposts) {
					Text("Reposts")
				}
				
				Toggle(isOn: $likes) {
					Text("Likes")
				}
				
				Section {
					Toggle(isOn: $onlyFromFollowed) {
						Text("Only from people you follow")
					}
				}
			}
		}
	}
}
