//
//  Warnings.swift
//  topaz
//
//  Created by Tanner Silva on 3/23/23.
//

import SwiftUI

struct RedWarningView: View {
	var body: some View {
		HStack(alignment: .center) {
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundColor(.red)
				.font(.system(size: 20))
			Text("This build is flagged as a 'Technical Preview'. Most features are nonfunctional and not intended for direct evaluation.")
				.font(.system(size: 14))
				.foregroundColor(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding()
		.background(Color(.secondarySystemBackground))
		.cornerRadius(8)
		.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.4), lineWidth: 2))
	}
}

struct NoticeView: View {
	var body: some View {
		HStack(alignment: .center) {
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundColor(.yellow)
				.font(.system(size: 20))
			Text("Please note that this is an early technical preview of Topaz. As we continue to develop the vision for this product, your feedback is appreciated.")
				.font(.system(size: 14))
				.foregroundColor(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding()
		.background(Color(.secondarySystemBackground))
		.cornerRadius(8)
		.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow.opacity(0.4), lineWidth: 2))
	}
}

struct UnderConstructionView: View {
	let unavailableViewName: String
	@State private var isFlashing = false
	@State private var flashingTask: Task<Void, Never>? = nil

	var body: some View {
		ZStack {
			Color(.systemBackground)
				.edgesIgnoringSafeArea(.all)

			VStack(spacing: 20) {
				Image(systemName: "lightbulb.fill")
					.resizable()
					.scaledToFit()
					.frame(width: 100, height: 100)
					.foregroundColor(isFlashing ? .yellow : .orange)
					.onChange(of: isFlashing) { _ in
						flashingTask?.cancel()
						flashingTask = Task {
							while true {
								await Task.sleep(400_000_000)
								withAnimation(Animation.linear(duration:0.4)) {
									isFlashing.toggle()
								}
								await Task.sleep(400_000_000)
							}
						}
					}
					.onAppear {
						isFlashing = true
					}
					.onDisappear {
						flashingTask?.cancel()
					}

				Text("\(unavailableViewName) Under Development")
					.font(.largeTitle)
					.fontWeight(.bold)
					.foregroundColor(.primary)
					.multilineTextAlignment(.center)
					.lineLimit(nil)

				Text("We're crafting the vision for this feature. Please stay tuned for future updates.")
					.font(.body)
					.fontWeight(.medium)
					.foregroundColor(.secondary)
					.multilineTextAlignment(.center)
					.padding(.horizontal, 40)
			}
		}
	}
}
