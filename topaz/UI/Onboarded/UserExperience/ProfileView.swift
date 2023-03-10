//
//  ProfileView.swift
//  topaz
//
//  Created by Tanner Silva on 3/9/23.
//

import SwiftUI

enum ProfileTab: Hashable {
	case posts
	case following
}

enum FollowState {
	case follows
	case following
	case unfollowing
	case unfollows
}

func follow_btn_txt(_ fs: FollowState, follows_you: Bool) -> String {
	switch fs {
	case .follows:
		return NSLocalizedString("Unfollow", comment: "Button to unfollow a user.")
	case .following:
		return NSLocalizedString("Following...", comment: "Label to indicate that the user is in the process of following another user.")
	case .unfollowing:
		return NSLocalizedString("Unfollowing...", comment: "Label to indicate that the user is in the process of unfollowing another user.")
	case .unfollows:
		if follows_you {
			return NSLocalizedString("Follow Back", comment: "Button to follow a user back.")
		} else {
			return NSLocalizedString("Follow", comment: "Button to follow a user.")
		}
	}
}

func follow_btn_enabled_state(_ fs: FollowState) -> Bool {
	switch fs {
	case .follows:
		return true
	case .following:
		return false
	case .unfollowing:
		return false
	case .unfollows:
	   return true
	}
}

func followersCountString(_ count: Int, locale: Locale = Locale.current) -> String {
	let bundle = bundleForLocale(locale: locale)
	return String(format: bundle.localizedString(forKey: "followers_count", value: nil, table: nil), locale: locale, count)
}

func relaysCountString(_ count: Int, locale: Locale = Locale.current) -> String {
	let bundle = bundleForLocale(locale: locale)
	return String(format: bundle.localizedString(forKey: "relays_count", value: nil, table: nil), locale: locale, count)
}


struct ProfileView: View {
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}
