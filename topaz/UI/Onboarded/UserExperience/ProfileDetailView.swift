//
//  ProfileDetailView.swift
//  topaz
//
//  Created by Tanner Silva on 3/29/23.
//

import Foundation
import SwiftUI

struct ProfileDetailView: View {
	let pubkey:String
	@State var profile: nostr.Profile // Load the user profile data here

	var body: some View {
		VStack {
			UpperProfileView(profile: $profile)
		}
	}
}

struct UpperProfileView: View {
	@Binding var profile: nostr.Profile

	var body: some View {
		VStack(alignment: .leading) {
			ZStack(alignment: .bottom) {
				if let banner = profile.banner, let bannerURL = URL(string: banner) {
					AsyncImage(url: bannerURL) { image in
						image.resizable()
							.scaledToFill()
					} placeholder: {
						RoundedRectangle(cornerRadius: 0)
							.fill(Color.gray)
					}
					.frame(height: 200)
					.clipped()
				}

				HStack {
					if let picture = profile.picture, let pictureURL = URL(string: picture) {
						AsyncImage(url: pictureURL) { image in
							image.resizable()
								.aspectRatio(contentMode: .fill)
						} placeholder: {
							ProgressView()
						}
						.frame(width: 50, height: 50)
						.clipShape(Circle())
						.padding(.trailing, 8)
					}

					VStack(alignment: .leading, spacing: 2) {
						HStack(spacing: 4) {
							DisplayNameText(text: profile.display_name ?? profile.name ?? "Unknown")

							if profile.nip05 != nil {
								Image(systemName: "checkmark.circle.fill")
									.foregroundColor(.blue)
									.font(.system(size: 18))
							}
						}

						if let name = profile.name {
							Text("@\(name)")
								.font(.subheadline)
								.foregroundColor(.gray)
						}
					}

					Spacer()

					VStack {
						Button(action: {
							// Direct messaging action
						}) {
							Image(systemName: "envelope.fill")
								.font(.title2)
								.padding()
						}
						.foregroundColor(Color.blue)

						// Other action buttons can be added here
					}
				}
				.padding(.bottom, 16)
				.padding(.horizontal, 16)
				.background(LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0), Color.black.opacity(0.6)]), startPoint: .top, endPoint: .bottom))
			}

			VStack(alignment: .leading, spacing: 8) {
				if let about = profile.about {
					Text(about)
						.font(.body)
						.padding(.horizontal, 16)
				}

				if let website = profile.website {
					if let asActionableURL = URL(string:website) {
						Link("Website: \(website)", destination:asActionableURL)
							.padding(.horizontal, 16)
					} else {
						Text("Website: \(website)")
					}
				}
			}
			.padding(.bottom, 16)
		}
	}
}
