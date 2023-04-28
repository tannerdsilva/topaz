//
//  TermsOfServiceView.swift
//  topaz
//
//  Created by Tanner Silva on 4/25/23.
//

import Foundation
import SwiftUI

struct TermsOfServiceScreen:View {
	@ObservedObject var appData:ApplicationModel
	
	var body:some View {
		if (appData.isTOSAcknowledged == nil) {
			Button("Accept TOS", action: {
				appData.isTOSAcknowledged = Date()
			})
		} else {
			Text("The TOS have already been acknowledged")
		}
	}
}
