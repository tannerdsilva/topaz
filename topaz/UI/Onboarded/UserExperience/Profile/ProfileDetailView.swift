//
//  ProfileDetailView.swift
//  topaz
//
//  Created by Tanner Silva on 3/29/23.
//

import Foundation
import SwiftUI

struct HeaderOffsetKey: PreferenceKey {
	static var defaultValue: CGFloat = 0
	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
		value = nextValue()
	}
}
struct ProfileDetailView: View {
	@Environment(\.presentationMode) var presentationMode
	let dbux:DBUX
	let pubkey:nostr.Key
	let profile:nostr.Profile
	let showBack:Bool

	@ObservedObject var profileEngine:DBUX.ProfilesEngine // Load the user profile data here

	var body: some View {
		if showBack {
			UpperProfileView(dbux:dbux, pubkey:pubkey, profile:profile).navigationBarBackButtonHidden(true).toolbar {
				ToolbarItem(placement: .navigationBarLeading) {
					CustomBackButton()
				}
			}.modifier(DragToDismiss(threshold:0.3))
		} else {
			UpperProfileView(dbux:dbux, pubkey:pubkey, profile:profile).navigationBarBackButtonHidden(true)
		}
	}
}

struct UpperProfileView: View {
	struct BannerVisualContentView: View {
		let dbux:DBUX
		let bannerURL: URL?

		var body: some View {
			if let url = bannerURL {
				UI.Images.AssetPipeline.AsyncImage(url: url, actor:dbux.storedImageActor) { image in
					image.resizable()
						.scaledToFill()
				} placeholder: {
					UI.AbstractView()
				}
			} else {
				UI.AbstractView()
			}
		}
	}
	
	struct ProfilePictureView: View {
		let dbux:DBUX
		let pictureURL: URL?

		var body: some View {
			Group {
				if let url = pictureURL {
					UI.Images.AssetPipeline.AsyncImage(url: url, actor:dbux.storedImageActor) { image in
						image.resizable()
							.aspectRatio(contentMode: .fill)
					} placeholder: {
						ProgressView()
					}
				} else {
					ProgressView()
				}
			}
			.frame(width: 50, height: 50)
			.clipShape(Circle())
		}
	}
	
	struct ProfileFullNameView: View {
		var displayName: String?
		var userName: String?
		var displayEmojis: Bool
		var isVerified: Bool = false
		var isPrimary: Bool

		var body: some View {
			HStack(spacing: 4) {
				let name = displayName ?? userName ?? "Unknown"
				Text(displayEmojis ? name : name.noEmoji)
					.font(isPrimary ? .headline : .subheadline)
					.foregroundColor(isPrimary ? Color.primary : .gray.opacity(0.6))
					.fontWeight(isPrimary ? .semibold : .regular)

				if isVerified && isPrimary {
					Image(systemName: "checkmark.circle.fill")
						.foregroundColor(.blue)
						.font(.system(size: 18))
				}
			}
		}
	}

	struct ProfileUsernameView: View {
		var userName: String?
		var isVerified: Bool = false
		var isPrimary: Bool

		var body: some View {
			HStack(spacing: 2) {
				Image(systemName: "at")
					.foregroundColor(isPrimary ? .gray : .gray.opacity(0.6))
					.font(.system(size: isPrimary ? 12 : 8))
					.opacity(0.5)

				let cleanUserName = (userName ?? "Unknown").noEmoji
				Text(cleanUserName)
					.font(isPrimary ? .headline : .subheadline)
					.foregroundColor(isPrimary ? Color.primary : .gray.opacity(0.6))
					.fontWeight(isPrimary ? .semibold : .regular)

				if isVerified && isPrimary {
					Image(systemName: "checkmark.circle.fill")
						.foregroundColor(.blue)
						.font(.system(size: 18))
				}
			}
		}
	}


	struct DisplayNameView: View {
		let dbux: DBUX
		var displayName: String?
		var userName: String?
		var isVerified: Bool
		@ObservedObject var contextEngine: DBUX.ContextEngine
		
		init(dbux: DBUX, displayName: String?, userName: String?, isVerified: Bool = false) {
			self.dbux = dbux
			contextEngine = dbux.contextEngine
			self.displayName = displayName
			self.userName = userName
			self.isVerified = isVerified
		}
		
		var body: some View {
			VStack(alignment: .leading, spacing: 2) {
						let appearanceSettings = contextEngine.userPreferences.appearanceSettings
						let namePriority = appearanceSettings.namePriorityPreference
						let displayEmojis = appearanceSettings.displayEmojisInNames

						if namePriority == .fullNamePreferred {
							ProfileFullNameView(displayName: displayName, userName: userName, displayEmojis: displayEmojis, isVerified: isVerified, isPrimary: true)
							if let username = userName {
								ProfileUsernameView(userName: username, isPrimary: false)
							}
						} else {
							ProfileUsernameView(userName: userName ?? "Unknown", isVerified: isVerified, isPrimary: true)
							if let fullname = displayName {
								ProfileFullNameView(displayName: fullname, displayEmojis: displayEmojis, isPrimary: false)
							}
						}
					}
			}
	}

	
	struct ProfileInfoView: View {
		let profile: nostr.Profile

		struct WebsiteLinkView: View {
			let website: String

			var body: some View {
				if let asActionableURL = URL(string: website) {
					Link("Website: \(website)", destination: asActionableURL)
				} else {
					Text("Website: \(website)")
				}
			}
		}

		var body: some View {
			VStack(alignment: .leading, spacing: 8) {
				if let about = profile.about {
					Text(about)
						.padding(.horizontal, 16)
				}

				if let website = profile.website {
					WebsiteLinkView(website: website)
						.padding(.horizontal, 16)
				}
			}
			.padding(.bottom, 16)
		}
	}
	
	struct BannerBackgroundWithGradientView:View {
		let dbux:DBUX
		let pubkey:nostr.Key
		let profile: nostr.Profile
		var body:some View {
			GeometryReader { innerGeometry in
				// can expand beyond safe area
				ZStack(alignment: .bottom) {
					BannerVisualContentView(dbux:dbux, bannerURL: profile.banner.flatMap { URL(string: $0) })
						.frame(width: innerGeometry.size.width, height: innerGeometry.size.height).clipped()
					
					LinearGradient(gradient: Gradient(colors: [
						Color.black.opacity(0),
						Color.black.opacity(0.10),
						Color.black.opacity(0.35),
						Color.black.opacity(0.55),
						Color.black.opacity(0.75),
						Color.black.opacity(0.92)
					]), startPoint: .top, endPoint: .bottom)
					.frame(width: innerGeometry.size.width, height: innerGeometry.size.height)
					.edgesIgnoringSafeArea(.top)
				}
			}
		}
	}
	
	@Environment(\.sizeCategory) var sizeCategory
	let dbux:DBUX
	let pubkey:nostr.Key
	let profile: nostr.Profile
	@State var showSheet = false
	@State private var headerOffset: CGFloat = 0
	var body: some View {
		 GeometryReader { geometry in
			 ScrollView {
				 ScrollViewReader { scrollProxy in
					 VStack(alignment: .leading) {
						 
						 // big mega z stack
						 ZStack(alignment: .bottom) {
							 GeometryReader { innerGeometry in
								 BannerBackgroundWithGradientView(dbux: dbux, pubkey: pubkey, profile: profile)
								 // VStack with frame inside safe area
								 VStack(alignment: .trailing) {
									 if (dbux.keypair.pubkey == pubkey) {
										 HStack {
											 NavigationLink(destination: UI.UserExperienceSettingsScreen(dbux:dbux)) { // Replace with the destination view for your settings
												 Image(systemName: "gear")
													 .font(.system(size: 18)) // Adjust the font size to make the button smaller
													 .foregroundColor(.white)
													 .padding(10) // Adjust padding to match the size of the RoundedRectangle
													 .background(RoundedRectangle(cornerRadius: 25) // RoundedRectangle with a corner radius matching half of the frame height
														.fill(Color.black.opacity(0.25))) // Fill the RoundedRectangle with a semi-transparent primary color
													 .frame(width: 50, height: 50) // Set the frame size of the RoundedRectangle
												 
											 }
											 Spacer()
											 NavigationLink(destination: UI.Profile.ProfileMetadataEditView(dbux:dbux, profile: profile, pubkey: pubkey.description)) {
												 Text("Edit")
													 .font(.system(size: 14))
													 .foregroundColor(.white)
													 .padding(.horizontal, 12)
													 .padding(.vertical, 6)
													 .background(Color.blue)
													 .cornerRadius(4)
											 }
										 }
										 .padding(.top, innerGeometry.safeAreaInsets.top)
										 .padding(.horizontal, 13)
										 .frame(width: geometry.size.width, alignment: .trailing)
									 }
									 Spacer()
									 HStack(alignment: .center) {
										 ProfilePictureView(dbux:dbux, pictureURL: URL(string: profile.picture ?? ""))
											 .padding(.trailing, 8)
										 
										 DisplayNameView(dbux:dbux, displayName: profile.display_name, userName: profile.name, isVerified: profile.nip05 != nil)
										 
										 HStack {
											 Spacer()
											 
											 UI.Profile.Actions.BadgeButton(dbux:dbux, pubkey: pubkey, profile:profile, sheetActions:[.dmButton, .sendTextNoteButton, .shareButton], showModal: $showSheet)
											 
										 }.contentShape(Rectangle()).frame(height:50)
											 .background(Color.clear)
											 .gesture(
												TapGesture()
													.onEnded { _ in
														showSheet.toggle()
													}
											 )
									 }
									 .padding(.horizontal, 16)
								 }
								 .padding(.top, geometry.safeAreaInsets.top)
							 }.background(GeometryReader { proxy in
								 Color.clear.preference(key: HeaderOffsetKey.self, value: proxy.frame(in: .named("scroll")).minY)
							 })
						 }
						 .offset(y: max(-headerOffset, 0))
						 .edgesIgnoringSafeArea(.top)
						 .frame(width: geometry.size.width, height: 220)
						 
						 ProfileInfoView(profile:profile)
						 Spacer()
					 }
					 // Apply the onPreferenceChange modifier
								.onPreferenceChange(HeaderOffsetKey.self) { offset in
									headerOffset = offset
								}
								.coordinateSpace(name: "scroll")
				 }
			 }
			 .offset(y: max(-headerOffset, 0))
			 .edgesIgnoringSafeArea(.top)
		 }
	 }
 }
