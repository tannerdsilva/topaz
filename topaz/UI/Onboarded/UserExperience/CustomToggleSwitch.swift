//
//  CustomToggleSwitch.swift
//  topaz
//
//  Created by Tanner Silva on 4/16/23.
//

import Foundation
import SwiftUI

import SwiftUI

struct CustomToggle: View {
	@Binding var isOn: Bool

	var body: some View {
		GeometryReader { geometry in
			ZStack {
				RoundedRectangle(cornerRadius: 12)
					.foregroundColor(isOn ? .blue : .gray)
					.frame(
						width: min(geometry.size.width, 50),
						height: min(geometry.size.width * 0.6, 30)
					)
					.animation(.easeInOut(duration: 0.2), value: isOn)

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
					isOn.toggle()
				}
			}
		}
	}
}
