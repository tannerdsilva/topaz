//
//  FollowsYouView.swift
//  topaz
//
//  Created by Tanner Silva on 4/21/23.
//

import Foundation
import SwiftUI

extension UI.Profile {
	struct FollowsYouView:View {
		var body: some View {
			HStack(alignment: .center) {
				Image(systemName: "checkmark")
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(height: 9)
					.foregroundColor(Color(.systemGreen))
					.padding(.top, 4)
					.padding(.bottom, 4)
					.padding(.leading, 12)
				
				Text("Follows you")
					.foregroundColor(Color(.systemGray))
					.font(.footnote)
					.padding(.top, 4)
					.padding(.bottom, 4)
					.padding(.trailing, 12)
			}.background {
				RoundedRectangle(cornerRadius: 5.0)
					  .foregroundColor(Color(.systemGray5))
			}
		}
	}
}
