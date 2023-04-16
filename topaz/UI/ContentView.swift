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
		if (appData.state == .onboarded) {
			UserExperienceView(dbux:appData.currentUX!).background(.yellow)
		} else {
			UI.OnboardingView(appData:appData)
		}
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
		ContentView(appData:Topaz().localData)
    }
}
