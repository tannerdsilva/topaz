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
		let dbux:DBUX
		let myView: DBUX.ViewMode
		let icon: String
		let index: Int
		@Binding var selectedTab: DBUX.ViewMode
		let accentColor: Color
		@Binding var showBadge: Bool
		var profileIndicate: nostr.Profile?
		@Environment(\.sizeCategory) var sizeCategory
		private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
		let longPressAction: () -> Void // Add a closure for the long press action
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
						if let profileImgUrl = profileIndicate?.picture, let hasURL = URL(string:profileImgUrl) {
							CachedAsyncImage(url:hasURL, imageCache: dbux.imageCache, content: { image in
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
			.simultaneousGesture(
				TapGesture()
					.onEnded { _ in
						// This space is intentionally left empty, as the Button action handles the tap
					}
					.simultaneously(with: LongPressGesture(minimumDuration: 0.5).onEnded { _ in
						longPressAction()
					})
			)
		}
	}


	struct NavBar: View {
		let dbux:DBUX
		@ObservedObject var appData:ApplicationModel
		@Binding var viewMode: DBUX.ViewMode
		@Binding var badgeStatus: DBUX.ViewBadgeStatus
		@Binding var showAccountPicker:Bool
		private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
		
		var body: some View {
			HStack {
				NavButton(dbux:dbux, myView: .home, icon: "house.fill", index: 0, selectedTab: $viewMode, accentColor: .orange, showBadge: $badgeStatus.homeBadge, profileIndicate: nil, longPressAction: {})
					.frame(maxWidth: .infinity, maxHeight: .infinity)

				NavButton(dbux:dbux, myView: .notifications, icon: "bell.fill", index: 1, selectedTab: $viewMode, accentColor: .cyan, showBadge: $badgeStatus.notificationsBadge, profileIndicate: nil, longPressAction: {})
					.frame(maxWidth: .infinity, maxHeight: .infinity)

				NavButton(dbux:dbux, myView: .dms, icon: "envelope.fill", index: 2, selectedTab: $viewMode, accentColor: .pink, showBadge: $badgeStatus.dmsBadge, profileIndicate: nil, longPressAction: {})
					.frame(maxWidth: .infinity, maxHeight: .infinity)

				NavButton(dbux:dbux, myView: .search, icon: "magnifyingglass", index: 3, selectedTab: $viewMode, accentColor: .orange, showBadge: $badgeStatus.searchBadge, profileIndicate: nil, longPressAction: {})
					.frame(maxWidth: .infinity, maxHeight: .infinity)

				NavButton(dbux:dbux, myView: .profile, icon: "person.fill", index: 4, selectedTab: $viewMode, accentColor: .cyan, showBadge: $badgeStatus.profileBadge, profileIndicate:dbux.eventsEngine.profilesEngine.currentUserProfile, longPressAction: {
					showAccountPicker = true
				}) // Pass the profile image here
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					
			}
			.frame(maxWidth: .infinity).background(Color(.systemBackground)).sheet(isPresented:$showAccountPicker, onDismiss: { showAccountPicker = false }, content: {
				UI.Account.PickerScreen(dbux:dbux)
			})
		}
	}
}
