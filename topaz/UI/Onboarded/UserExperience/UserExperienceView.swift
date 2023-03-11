//
//  UserExperienceView.swift
//  topaz
//
//  Created by Tanner Silva on 3/6/23.
//

import SwiftUI

struct UserExperienceView: View {
	@ObservedObject var ue:UE

    var body: some View {
		NavigationStack {
			VStack {
				VStack {
					// Title Bar
					Text(ue.uuid)
						.fontWeight(.bold)
						.padding(.top)
				}.frame(height: 44).background(.green)
				
				Spacer()
				
				if ue.viewMode == .timeline {
					TimelineView(ue:ue)
				} else {
					UEDevView(ue:ue)
				}
				// Main content goes here
				
				Spacer()
				
				// Navigation Bar
				HStack {
					Spacer()
					Button("Timeline") {
						// Navigate to home screen
						ue.viewMode = .timeline
					}
					Spacer()
					Button("Dev") {
						// Navigate to profile screen
						ue.viewMode = .devView
					}
					Spacer()
				}
				.padding().background(.red)
			}.background(.gray)
		}
    }
}

struct UserExperienceView_Previews: PreviewProvider {
    static var previews: some View {
		UserExperienceView(ue:try! UE(publicKey:"foo"))
    }
}
