//
//  ContentView.swift
//  topaz
//
//  Created by Tanner Silva on 3/5/23.
//

import SwiftUI

struct ContentView: View {
	@ObservedObject var appData:ApplicationModel
	
    var body: some View {
//		if let hasCurrentUX = appData.currentUX {
			if (appData.state == .operating) {
				if let hasUX = appData.currentUX {
					UserExperienceView(dbux:hasUX)
				} else {
					UI.Account.PickerScreen(app:appData)
				}
				
			} else {
				UI.OnboardingView(appData:appData)
			}
//		}
    }
}
