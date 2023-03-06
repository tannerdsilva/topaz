//
//  ContentView.swift
//  topaz
//
//  Created by Tanner Silva on 3/5/23.
//

import SwiftUI

struct ContentView: View {
	@StateObject var appData:ApplicationModel
	
    var body: some View {
		if (appData.state == .onboarded) {
			Text(verbatim: "IDK WHAT THIS SHOULD BE YET")
			Button("Revert onboarding") {
				appData.state = .welcomeFlow
			}
		} else {
			OnboardingView(appData:appData)
		}
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
		ContentView(appData:Topaz().localData)
    }
}
