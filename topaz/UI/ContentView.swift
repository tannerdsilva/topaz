//
//  ContentView.swift
//  topaz
//
//  Created by Tanner Silva on 3/5/23.
//

import SwiftUI

struct ContentView: View {
	@State var appData:ApplicationModel.Metadata
	
    var body: some View {
		VStack {
			if (appData.state == .onboarded) {
				Text("Thank you for acknowledging the TOS")
			} else {
				Text("Please acknowledge the TOS")
			}
			Button("OK I acknowledge", action: {
				appData.state = .onboarded
			}).foregroundColor(.blue)
		}
        
		
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
		ContentView(appData:Topaz().localData)
    }
}
