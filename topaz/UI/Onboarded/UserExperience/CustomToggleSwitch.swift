//
//  CustomToggleSwitch.swift
//  topaz
//
//  Created by Tanner Silva on 4/16/23.
//

import Foundation
import SwiftUI

extension UI {
	struct CustomToggle: View {
		@Binding var isOn: Bool
		var symbolOn: String
		var symbolOff: String
		
		private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

		var body: some View {
			GeometryReader { geometry in
				ZStack {
					RoundedRectangle(cornerRadius: 12)
						.stroke(isOn ? Color.blue : Color.gray, lineWidth:1)
						.frame(
							width: min(geometry.size.width, 50),
							height: min(geometry.size.width * 0.6, 30)
						)
						.animation(.easeInOut(duration: 0.2), value: isOn)

					HStack {
						Image(systemName: symbolOn) // Inverted
							.resizable()
							.scaledToFit()
							.frame(width: 12, height: 12)
							.foregroundColor(.blue)
						
						Spacer()
						
						Image(systemName: symbolOff) // Inverted
							.resizable()
							.scaledToFit()
							.frame(width: 12, height: 12)
							.foregroundColor(.gray)
					}
					.frame(width: min(geometry.size.width * 0.8, 40))

					Circle()
						.frame(
							width: min(geometry.size.width * 0.52, 26),
							height: min(geometry.size.width * 0.52, 26)
						)
						.foregroundColor(.white)
						.offset(x: isOn ? min(geometry.size.width * 0.2, 10) : -min(geometry.size.width * 0.2, 10))
						.animation(.easeInOut(duration: 0.2), value: isOn)
				}
				.frame(width: geometry.size.width, height: geometry.size.height)
				.onTapGesture {
					withAnimation {
						feedbackGenerator.impactOccurred()
						isOn.toggle()
					}
				}
			}
		}
	}
}

