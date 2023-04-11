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
	
	@StateObject var appData:ApplicationModel
	@State var progress:OnboardingProgress = .hello
	
	struct WelcomeView: View {
		@StateObject var appData:ApplicationModel
		@Binding var progress:OnboardingProgress
		
		var body: some View {
			VStack {
				Spacer()
				RedWarningView()
				Spacer()
				
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
					Button(action: {
						progress = .createNewAcknowledge
					}, label: {
						Text("Create New")
					}).disabled(true)
				}
				.padding(.horizontal, 12.0)
				Spacer()
			}
		}
	}
	
	struct ExistingLoginView: View {
		@StateObject var appData: ApplicationModel // data store
		@Binding var progress: OnboardingProgress // will always equal `.existingInput` in this view
		@State var nsecKey: String = ""    // private key

		@State var parsedKey: ParsedKey? = nil // the private key that was successfully parsed from the user input from `nsecKey`
		@State var tfDisabled: Bool = false

		@FocusState var tfFocus: Bool
		
		func textFieldStrokeColor(tfFocus: Bool, tfDisabled: Bool) -> Color {
			if tfFocus {
				if tfDisabled {
					return Color.green
				} else {
					return Color.blue
				}
			} else {
				return Color(.darkGray)
			}
		}
		
		var body: some View {
			VStack {
				if case .priv(_) = parsedKey {
					Text(verbatim: "This key is validated!")
						.font(.headline)
						.foregroundColor(Color.green)
						.padding(.bottom)
				} else {
					Text(verbatim: "Please enter your private key...")
						.font(.headline)
						.foregroundColor(Color.primary)
						.padding(.bottom)
				}
				HStack {
					if case .priv(_) = parsedKey, tfDisabled == true {
						Button("Edit Key") {
							tfDisabled = false
							tfFocus = true
						}
						.padding()
						.background(Color.blue)
						.foregroundColor(Color.white)
						.cornerRadius(8)
					}
					TextField("nsec.........", text: $nsecKey).onChange(of: nsecKey, perform: { newValue in
						if let hasParsedItem = parse_key(newValue) {
							if hasParsedItem != parsedKey {
								parsedKey = hasParsedItem
								if case .priv(_) = parsedKey {
									tfDisabled = true
								}
							}
						} else if parsedKey != nil {
							parsedKey = nil
						}
					})
					.padding()
					.background(Color(.systemGray6))
					.cornerRadius(8)
					.disabled(tfDisabled)
					.focused($tfFocus)
					.overlay(RoundedRectangle(cornerRadius: 8).stroke(textFieldStrokeColor(tfFocus:tfFocus, tfDisabled: tfDisabled), lineWidth: 2))
				}.padding(.horizontal, 16.0)
				if case let .priv(pk) = parsedKey {
					if let getPub = privkey_to_pubkey(privkey: pk) {
						Button("Login") { [getPK = pk, gPub = getPub] in
							do {
								try appData.installUser(publicKey: gPub, privateKey: getPK)
							} catch let error {
							}
						}
						.padding()
						.background(Color.blue)
						.foregroundColor(Color.white)
						.cornerRadius(8)
					} else {
						Text("There was a problem getting the private key")
							.font(.callout)
							.foregroundColor(Color.red)
					}
				}
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

fileprivate func parse_key(_ thekey: String) -> ParsedKey? {
	var key = thekey
	if key.count > 0 && key.first! == "@" {
		key = String(key.dropFirst())
	}

	if hex_decode(key) != nil {
		return .hex(key)
	}

	if (key.contains { $0 == "@" }) {
		return .nip05(key)
	}

	if let bech_key = decode_bech32_key(key) {
		switch bech_key {
		case .pub(let pk):
			return .pub(pk)
		case .sec(let sec):
			return .priv(sec)
		}
	}
	return nil
}
