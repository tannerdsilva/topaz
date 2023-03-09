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
			UserExperienceView(ue:appData.defaultUE!)
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
