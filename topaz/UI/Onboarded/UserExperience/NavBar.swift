//
//  NavBar.swift
//  topaz
//
//  Created by Tanner Silva on 4/16/23.
//

import Foundation
import SwiftUI

extension UI {
	struct NavButton: View {
		let myView: DBUX.ViewMode
		let icon: String
		let index: Int
		@Binding var selectedTab: DBUX.ViewMode
		let accentColor: Color
		@Binding var showBadge: Bool
		@State var profileIndicate: nostr.Profile?
		@Environment(\.sizeCategory) var sizeCategory

		var imageSize: CGFloat {
			switch sizeCategory {
			case .accessibilityExtraExtraExtraLarge:
				return 45
			case .accessibilityExtraExtraLarge, .accessibilityExtraLarge, .accessibilityLarge, .accessibilityMedium:
				return 32
			default:
				return 22
			}
		}
		
		var badgeSize: CGFloat {
			return imageSize * 0.420 // blaze it
		}
		
		var body: some View {
			Button(action: {
				selectedTab = myView
				showBadge = false
			}) {
				GeometryReader { geometry in
					ZStack {
						if let profileImgUrl = profileIndicate?.picture {
							AsyncImage(url: URL(string:profileImgUrl), content: { image in
								image
									.resizable()
									.aspectRatio(contentMode: .fill)
									.frame(width: imageSize, height: imageSize)
									.clipShape(Circle())
							}, placeholder: {
								ProgressView()
									.frame(width: imageSize, height: imageSize)
							})
						} else {
							Image(systemName: icon)
								.resizable()
								.scaledToFit()
								.foregroundColor(selectedTab == myView ? accentColor : .gray)
								.frame(width: imageSize, height: imageSize)
						}
						
						if showBadge {
							GeometryReader { geometry in
								ZStack {
									Circle()
										.fill(Color.red)
										.frame(width: badgeSize, height: badgeSize)
								}
								.position(x: geometry.size.width, y: geometry.size.height * 0.11)
							}
						}
					}
					.frame(width: geometry.size.width, height: geometry.size.height)
				}
			}
			.background(Color.clear)
		}
	}


	struct NavBar: View {
		let dbux:DBUX
		@Binding var viewMode: DBUX.ViewMode
		@Binding var badgeStatus: DBUX.ViewBadgeStatus
		@State private var showAccountPicker = false
		
		var body: some View {
			HStack {
				NavButton(myView: .home, icon: "house.fill", index: 0, selectedTab: $viewMode, accentColor: .orange, showBadge: $badgeStatus.homeBadge, profileIndicate: nil)
					.frame(maxWidth: .infinity, maxHeight: .infinity).border(.pink)

				NavButton(myView: .notifications, icon: "bell.fill", index: 1, selectedTab: $viewMode, accentColor: .cyan, showBadge: $badgeStatus.notificationsBadge, profileIndicate: nil)
					.frame(maxWidth: .infinity, maxHeight: .infinity).border(.pink)

				NavButton(myView: .dms, icon: "envelope.fill", index: 2, selectedTab: $viewMode, accentColor: .pink, showBadge: $badgeStatus.dmsBadge, profileIndicate: nil)
					.frame(maxWidth: .infinity, maxHeight: .infinity).border(.pink)

				NavButton(myView: .search, icon: "magnifyingglass", index: 3, selectedTab: $viewMode, accentColor: .orange, showBadge: $badgeStatus.searchBadge, profileIndicate: nil)
					.frame(maxWidth: .infinity, maxHeight: .infinity).border(.pink)

				NavButton(myView: .profile, icon: "person.fill", index: 4, selectedTab: $viewMode, accentColor: .cyan, showBadge: $badgeStatus.profileBadge, profileIndicate:dbux.profilesEngine.currentUserProfile) // Pass the profile image here
					.frame(maxWidth: .infinity, maxHeight: .infinity).border(.pink)
					.onLongPressGesture {
					showAccountPicker.toggle()
				}
			}
			.frame(maxWidth: .infinity).background(Color(.systemBackground)).border(.yellow)
		}
	}
}
