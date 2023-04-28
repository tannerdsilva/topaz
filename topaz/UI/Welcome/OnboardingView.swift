//
//  OnboardingView.swift
//  topaz
//
//  Created by Tanner Silva on 3/5/23.
//

import SwiftUI

extension UI {
	struct OnboardingView: View {
		enum OnboardingProgress {
			case hello
			case existingInput
			case createNewAcknowledge
		}
		
		@StateObject var appData:ApplicationModel
		@State var progress:OnboardingProgress = .hello

		struct WelcomeView: View {
			struct LoginOptionsView: View {
				let appData:ApplicationModel
				var body: some View {
					HStack(alignment:.center) {
						VStack(spacing: 20) {
							NavigationLink(destination: ExistingLoginView(appData:appData)) {
								HStack {
									Image(systemName: "person")
										.font(.largeTitle)
									
									VStack(alignment: .leading) {
										Text("Log in")
											.font(.title2)
											.bold()
										
										Text("Use an existing account")
											.font(.callout)
											.foregroundColor(.gray)
									}
								}
								.padding()
								.background(Color.blue.opacity(0.1))
								.cornerRadius(20)
								.foregroundColor(.blue)
							}
							
							NavigationLink(destination: ExistingLoginView(appData:appData)) {
								HStack {
									Image(systemName: "person.badge.plus")
										.font(.largeTitle)
									
									VStack(alignment: .leading) {
										Text("Create account")
											.font(.title2)
											.bold()
										
										Text("Sign up for a new account")
											.font(.callout)
											.foregroundColor(.gray)
									}
								}
								.padding()
								.background(Color.green.opacity(0.1))
								.cornerRadius(20)
								.foregroundColor(.green)
							}
						}
					}
				}
			}

			struct WelcomeBackgroundView: View {
				let frontView:AbstractView
				let backView: AbstractView
				
				@State private var frontRotation = 0.0
				@State private var backRotation = 0.0
				
				init(seed: UInt64) {
					frontView = AbstractView(seed: seed)
					let complimentaryHue = (frontView.randomHue + 0.5).truncatingRemainder(dividingBy: 1.0)
					backView = AbstractView(hue: complimentaryHue, seed: seed + 1)
				}
				
				var body: some View {
					GeometryReader { geometry in
					   ZStack {
						   backView
							   .rotationEffect(Angle(degrees: backRotation))
							   .onAppear {
								   withAnimation(Animation.linear(duration: 960).repeatForever(autoreverses: false)) {
									   backRotation = -360
								   }
							   }
						   
						   frontView
							   .scaleEffect(0.5)
							   .rotationEffect(Angle(degrees: frontRotation))
							   .onAppear {
								   withAnimation(Animation.linear(duration: 960).repeatForever(autoreverses: false)) {
									   frontRotation = 360
								   }
							   }
						   
//						   LinearGradient(
//							   gradient: Gradient(stops: [
//								   .init(color: .clear, location: 1),
//								   .init(color: Color(.systemBackground), location: 0)
//							   ]),
//							   startPoint: .bottom,
//							   endPoint: .top
//						   )
						   
						   VStack {
							   Spacer()
							   Image("topaz-logo") // Replace "topaz-logo" with the correct name of your SVG asset
								   .resizable()
								   .renderingMode(.template)
								   .aspectRatio(contentMode: .fit)
								   .frame(width: 80, height: 80) // Set the dimensions to 80x80 points
								   .foregroundColor(Color.white).opacity(0.95)
							   Spacer()
						   }
					   }
					   .edgesIgnoringSafeArea(.all)
				   }
			   }
			}

			@ObservedObject var appData: ApplicationModel
			
			var body: some View {
				NavigationStack {
					VStack {
						WelcomeBackgroundView(seed:UInt64.random(in:0..<UInt64.max))
						
						VStack() {
							VStack(alignment:.leading) {
								VStack {
								   Text("Welcome to Topaz")
									   .font(.largeTitle)
									   .bold().opacity(0.85)
								   
								   Text("A high performance, censorship resistant social media experience with native crypto features.")
									   .font(.headline)
									   .multilineTextAlignment(.center).opacity(0.65)
							   }.padding(.horizontal, 15)
							}
							if (appData.isTOSAcknowledged != nil) {
								LoginOptionsView(appData: appData)
							}
							TermsOfServiceStatusRowView(appData:appData)
	//						HStack {
//								Toggle(isOn:$appData.isTOSAcknowledged) {
//									if (appData.isTOSAcknowledged) {
//										Text(verbatim:"Thanks :)")
//										Text("TOS has been acknowledged")
//									} else {
//										Text(verbatim:"Please acknowledge the TOS")
//									}
//								}
//								.padding()
	//							.frame(width: 300.0)
	//						}
	//						HStack {
	//							Button(action: {
	//								progress = .existingInput
	//							}, label: {
	//								Text("Login with npub")
	//							}).disabled(!appData.isTOSAcknowledged)
	//							Button(action: {
	//								progress = .createNewAcknowledge
	//							}, label: {
	//								Text("Create New")
	//							}).disabled(true)
	//						}
	//						.padding(.horizontal, 12.0)
						}.frame(height:300)
					}
				}
			}
		}

		
		struct ExistingLoginView: View {
			let appData: ApplicationModel // data store
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
									try appData.installUser(publicKey: nostr.Key(gPub)!, privateKey:nostr.Key(getPK)!)
								} catch {}
							}.padding()
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
				WelcomeView(appData:appData)
			case .existingInput:
				ExistingLoginView(appData: appData)
			case .createNewAcknowledge:
				Text("foo")
			}
			
		}
	}
}

extension UI {
	struct OnboardingView_Previews: PreviewProvider {
		static var previews: some View {
			OnboardingView(appData:Topaz().localData)
		}
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
