//
//  CustomBackButton.swift
//  topaz
//
//  Created by Tanner Silva on 5/1/23.
//

import Foundation
import SwiftUI

struct CustomBackButton: View {
	@Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
	
	var body: some View {
		Button(action: {
			self.presentationMode.wrappedValue.dismiss()
		}) {
			HStack {
				Image(systemName: "arrow.backward")
					.aspectRatio(contentMode: .fit)
					.foregroundColor(.blue)
				Text("Back")
					.foregroundColor(.blue)
			}
		}
	}
}
