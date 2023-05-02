//
//  FollowUnfollowButton.swift
//  topaz
//
//  Created by Tanner Silva on 5/1/23.
//

import Foundation
import SwiftUI

extension UI.Profile {
	struct FollowUnfollowButton: View {
		@State private var isFollowing: Bool = false
		
		var body: some View {
			Button(action: {
							self.isFollowing.toggle()
						}) {
							Text(isFollowing ? "Unfollow" : "Follow")
								.font(.system(size: 14))
								.foregroundColor(isFollowing ? .black : .white)
								.padding(.horizontal, 12)
								.padding(.vertical, 6)
								.background(isFollowing ? Color.white : Color.gray)
								.cornerRadius(4)
								.overlay(
									RoundedRectangle(cornerRadius: 4)
										.stroke(Color.black, lineWidth: 1)
								)
						}
		}
	}
}
