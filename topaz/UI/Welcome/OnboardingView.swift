//
//  OnboardingView.swift
//  topaz
//
//  Created by Tanner Silva on 3/5/23.
//

import SwiftUI

struct OnboardingView: View {
	enum OnboardingProgress {
		case hello
		case existingInput
		case createNewAcknowledge
	}
	@State var progress:OnboardingProgress = .hello
	@State var tosAcknowledged = false
    var body: some View {
		NavigationStack {
			VStack {
				Text(verbatim: "WELCOME! You are here early.")
					.padding(.bottom)
				HStack {
					Toggle(isOn:$tosAcknowledged) {
						if (tosAcknowledged) {
							Text(verbatim:"Thanks :)")
						} else {
							Text(verbatim:"Please acknowledge the TOS here ->")
						}
						Text("TOS acknowledge")
					}
					.padding()
					.frame(width: 300.0)
				}
				HStack {
//					Button("Login with existing")
				}
				HStack {
//					Button("Create new")
				}
			}
		}
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
