//
//  UserExperienceSettingsView.swift
//  topaz
//
//  Created by Tanner Silva on 4/23/23.
//

import SwiftUI

extension UI {
	struct UserExperienceSettingsScreen: View {
		let dbux:DBUX
		struct SettingsRow: View {
			var icon: String
			var title: String
			var isDestructive: Bool = false
			
			var body: some View {
				HStack {
					Image(systemName: icon)
						.foregroundColor(isDestructive ? .red : .accentColor)
						.imageScale(.large)
						.frame(width: 32, height: 32)
					
					Text(title)
						.foregroundColor(isDestructive ? .red : .primary)
				}
			}
		}
		
		var body: some View {
			NavigationView {
				List {
					SettingsRow(icon: "key", title: "Keys")
					NavigationLink(destination: UI.NotificationsSettingsView()) {
						SettingsRow(icon: "bell", title: "Notifications")
					}
					NavigationLink(destination:UI.UserPreferences.AppearanceScreen(dbux:dbux)) {
						SettingsRow(icon: "paintbrush", title: "Appearance")
					}
					NavigationLink(destination: UI.OpenAISettingsView()) {
						SettingsRow(icon: "brain", title: "OpenAI")
					}
					SettingsRow(icon: "globe", title: "Translate")
					SettingsRow(icon: "trash", title: "Destructive")
					
					Section {
						SettingsRow(icon: "arrowshape.turn.up.left", title: "Sign Out", isDestructive: true)
					}
				}
				.listStyle(InsetGroupedListStyle())
				.navigationTitle("Settings")
			}
		}
	}
	
}
