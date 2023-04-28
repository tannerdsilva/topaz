//
//  TermsOfServiceStatusView.swift
//  topaz
//
//  Created by Tanner Silva on 4/25/23.
//

import Foundation
import SwiftUI

struct TermsOfServiceStatusRowView: View {
	@ObservedObject var appData: ApplicationModel
	@Environment(\.colorScheme) var colorScheme
	
	var body: some View {
		NavigationLink(destination: TermsOfServiceScreen(appData: appData)) {
			if let date = appData.isTOSAcknowledged {
				HStack {
					Text("Our TOS was Acknowledged on \(formattedDate(date))")
						.font(.caption)
						.padding(.horizontal, 12)
						.padding(.vertical, 3)
					
					Image(systemName: "arrow.right")
						.padding(.trailing, 8)
				}
				.foregroundColor(buttonForegroundColor)
				.background(buttonBackgroundColor)
				.cornerRadius(20)
			} else {
				HStack {
					Image(systemName: "doc.text")
						.font(.largeTitle)

					VStack(alignment: .leading) {
						Text("View Terms")
							.font(.title2)
							.bold()

						Text("Read the Terms of Service")
							.font(.callout)
							.foregroundColor(.gray)
					}
				}
				.padding()
				.background(Color.yellow.opacity(0.1))
				.cornerRadius(20)
				.foregroundColor(.yellow)
			}
			
		}.padding()
	}
	
	private var buttonForegroundColor: Color {
		if appData.isTOSAcknowledged == nil {
			return .white
		} else {
			return colorScheme == .dark ? .white : .black
		}
	}
	
	private var buttonBackgroundColor: Color {
		if appData.isTOSAcknowledged == nil {
			return .blue
		} else {
			return colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1)
		}
	}
	
	private func formattedDate(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		return formatter.string(from: date)
	}
}
