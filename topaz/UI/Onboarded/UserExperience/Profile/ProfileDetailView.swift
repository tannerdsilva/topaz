//
//  ProfileDetailView.swift
//  topaz
//
//  Created by Tanner Silva on 3/29/23.
//

import Foundation
import SwiftUI

struct ProfileDetailView: View {
	let dbux:DBUX
	let pubkey:nostr.Key
	@ObservedObject var profileEngine:DBUX.ProfilesEngine // Load the user profile data here

	var body: some View {
		NavigationStack {
			UpperProfileView(dbux:dbux, pubkey:pubkey, profile: profileEngine.currentUserProfile)
		}
	}
}

struct UpperProfileView: View {
	struct BannerVisualContentView: View {
		let imageCache:ImageCache
		let bannerURL: URL?

		var body: some View {
			if let url = bannerURL {
				CachedAsyncImage(url: url, imageCache: imageCache) { image in
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
					CachedAsyncImage(url: url, imageCache: dbux.imageCache) { image in
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
	
	struct DisplayNameView: View {
		var displayName: String?
		var userName: String?
		var isVerified: Bool

		init(displayName: String?, userName: String?, isVerified: Bool = false) {
			self.displayName = displayName
			self.userName = userName
			self.isVerified = isVerified
		}

		var body: some View {
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 4) {
					Text(displayName ?? userName ?? "Unknown")
						.font(.headline)
						.fontWeight(.semibold)

					if isVerified {
						Image(systemName: "checkmark.circle.fill")
							.foregroundColor(.blue)
							.font(.system(size: 18))
					}
				}

				if let name = userName {
					Text("@\(name)")
						.font(.subheadline)
						.foregroundColor(.gray)
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
					UI.Events.UserFacingTextContentView(content: about)
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
					BannerVisualContentView(imageCache:dbux.imageCache, bannerURL: profile.banner.flatMap { URL(string: $0) })
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

	var body: some View {
		 GeometryReader { geometry in
			 VStack(alignment: .leading) {
				 ZStack(alignment: .bottom) {
					 GeometryReader { innerGeometry in
						 BannerBackgroundWithGradientView(dbux: dbux, pubkey: pubkey, profile: profile)
						 // VStack with frame inside safe area
						 VStack(alignment: .trailing) {
							 HStack {
								 NavigationLink(destination: UserExperienceSettingsView()) { // Replace with the destination view for your settings
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
							 
							 Spacer()
							 HStack(alignment: .center) {
								 ProfilePictureView(dbux:dbux, pictureURL: URL(string: profile.picture ?? ""))
									 .padding(.trailing, 8)
								 
								 DisplayNameView(displayName: profile.display_name, userName: profile.name, isVerified: profile.nip05 != nil)
								 
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
					 }
				 }
				 .edgesIgnoringSafeArea(.top)
				 .frame(width: geometry.size.width, height: 220)

				 ProfileInfoView(profile:profile)
				 Spacer()
			 }
		 }
	 }
 }
