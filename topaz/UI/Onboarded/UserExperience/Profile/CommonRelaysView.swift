//
//  CommonRelaysView.swift
//  topaz
//
//  Created by Tanner Silva on 4/21/23.
//

import Foundation
import SwiftUI

extension UI.Profile {
	struct CommonRelaysView: View {
		@State var relays: UInt?
		var body: some View {
			HStack(alignment: .center) {
				if relays != nil {
					Image(systemName: "circle.fill")
						.resizable()
						.aspectRatio(contentMode: .fit)
						.frame(height: 9)
						.foregroundColor(relays != nil && relays! > 0 ? Color(.systemGreen) : Color(.systemRed))
						.padding(.top, 4)
						.padding(.bottom, 4)
						.padding(.leading, 12)
				}
				Text(relays != nil ? "\(relays!)" : "?")
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
