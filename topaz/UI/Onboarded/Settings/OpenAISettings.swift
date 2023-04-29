//
//  OpenAISettings.swift
//  topaz
//
//  Created by Tanner Silva on 4/28/23.
//

import Foundation
import SwiftUI

extension UI {
	struct OpenAISettingsView: View {
		@State private var apiKey: String = ""

		var body: some View {
			NavigationView {
				VStack {
					TextField("Enter your OpenAI API key", text: $apiKey)
						.padding()
						.textFieldStyle(RoundedBorderTextFieldStyle())
						.disableAutocorrection(true)
						.autocapitalization(.none)
					
					Spacer()
				}
				.padding()
				.navigationTitle("OpenAI")
			}
		}
	}
}
