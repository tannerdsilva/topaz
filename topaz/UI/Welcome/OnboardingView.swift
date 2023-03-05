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
	
	@StateObject var appData:ApplicationModel.Metadata
	@State var progress:OnboardingProgress = .hello
	
	struct WelcomeView: View {
		@StateObject var appData:ApplicationModel.Metadata
		@Binding var progress:OnboardingProgress
		
		var body: some View {
			VStack {
				Text(verbatim: "WELCOME! You are here early.")
					.padding(.bottom)
				HStack {
					Toggle(isOn:$appData.isTOSAcknowledged) {
						if (appData.isTOSAcknowledged) {
							Text(verbatim:"Thanks :)")
							Text("TOS has been acknowledged")
						} else {
							Text(verbatim:"Please acknowledge the TOS")
						}
					}
					.padding()
					.frame(width: 300.0)
				}
				HStack {
					Button(action: {
						progress = .existingInput
					}, label: {
						Text("Login with npub")
					}).disabled(!appData.isTOSAcknowledged)
				}
				HStack {
					Button(action: {
						progress = .createNewAcknowledge
					}, label: {
						Text("Create New")
					}).disabled(!appData.isTOSAcknowledged)
				}
			}
		}
	}
	
	struct ExistingLoginView: View {
		@StateObject var appData:ApplicationModel.Metadata
		@Binding var progress:OnboardingProgress
		@State var nsecKey:String = ""
		
		var body: some View {
			VStack {
				Text(verbatim: "Please enter your nsec private key...")
					.padding(.bottom)
				TextField("nsec.........", text:$nsecKey)
			}
		}
	}

    var body: some View {
		switch progress {
		case .hello:
			WelcomeView(appData:appData, progress:$progress)
		case .existingInput:
			ExistingLoginView(appData: appData, progress: $progress)
		case .createNewAcknowledge:
			Text("foo")
		}
		
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
		OnboardingView(appData:Topaz().localData)
    }
}

