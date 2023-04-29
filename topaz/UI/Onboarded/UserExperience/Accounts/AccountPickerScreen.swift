//
//  AccountPickerView.swift
//  topaz
//
//  Created by Tanner Silva on 4/24/23.
//

import Foundation
import SwiftUI

extension UI.Account {
	struct PickerScreen: View {
		let dbux: DBUX
		@ObservedObject private var userStore: ApplicationModel.UserStore
		@State var showOnboarding: Bool = false
		@Environment(\.presentationMode) var presentationMode

		init(dbux: DBUX) {
			self.dbux = dbux
			self.userStore = dbux.application.userStore
		}

		var body: some View {
			NavigationStack {
				List(0..<userStore.users.count+1, id: \.self) { index in
					if index < userStore.users.count {
						let account = userStore.users[index]
						HStack {
							VStack(alignment: .leading, spacing: 4) {
								Text(account.profile.name ?? "NO NAME BRUH")
									.font(.headline)

								Text("Key ID: \(account.key.description)")
									.font(.subheadline)
									.foregroundColor(.gray)
							}
							Spacer()
						}.onTapGesture {
							withAnimation {
								try? dbux.application.setCurrentlyLoggedInUser(account.key)
								presentationMode.wrappedValue.dismiss()
							}
						}
					} else {
						Button(action: {
							showOnboarding = true
						}) {
							HStack {
								Spacer()
								Text("New Account")
									.font(.headline)
									.foregroundColor(.blue)
								Spacer()
							}
						}
					}
				}
				.navigationTitle("Account Picker")
				.navigationBarTitleDisplayMode(.large)
				.sheet(isPresented: $showOnboarding, onDismiss: { showOnboarding = false }, content: {
					UI.OnboardingView(appData: dbux.application)
				})
			}
		}
	}


}
