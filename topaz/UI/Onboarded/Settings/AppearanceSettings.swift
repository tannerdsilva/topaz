//
//  AppearanceSettings.swift
//  topaz
//
//  Created by Tanner Silva on 5/6/23.
//

import Foundation
import SwiftUI

extension UI {
	struct UserPreferences {
		struct AppearanceScreen: View {
			let dbux: DBUX
			@ObservedObject var contextEngine: DBUX.ContextEngine

			init(dbux: DBUX) {
				self.dbux = dbux
				self.contextEngine = dbux.contextEngine
			}

			var body: some View {
				NavigationView {
					List {
						Toggle(isOn: $contextEngine.userPreferences.appearanceSettings.alwaysShowEventActions) {
							Text("Always Show Event Actions")
						}
						Toggle(isOn: $contextEngine.userPreferences.appearanceSettings.displayEmojisInNames) {
							Text("Display Emojis in Names")
						}
						Picker("Name Priority Preference", selection: $contextEngine.userPreferences.appearanceSettings.namePriorityPreference) {
							Text("Full Name Preferred").tag(DBUX.ContextEngine.UserPreferences.Appearance.NamePriorityPreference.fullNamePreferred)
							Text("Username Preferred").tag(DBUX.ContextEngine.UserPreferences.Appearance.NamePriorityPreference.usernamePreferred)
						}
						Toggle(isOn: $contextEngine.userPreferences.appearanceSettings.doNotShowIdenticalNames) {
							Text("Do Not Show Identical Names")
						}
					}
					.navigationTitle("Appearance Preferences")
				}
			}
		}

	}
}
