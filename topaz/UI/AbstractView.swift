//
//  AbstractView.swift
//  topaz
//
//  Created by Tanner Silva on 4/25/23.
//

import Foundation
import SwiftUI

extension UI {
	struct AbstractView: View {
		struct SeededGenerator:RandomNumberGenerator {
			private var rng: SystemRandomNumberGenerator
			private var seed: UInt64
			
			init(seed: UInt64) {
				self.seed = seed
				self.rng = SystemRandomNumberGenerator()
			}
			
			mutating func next() -> UInt64 {
				seed = rng.next() ^ seed
				return seed
			}
		}
		
		static func generateRandomHueValue() -> Double {
			return Double.random(in:0..<1)
		}
		@Environment(\.colorScheme) var colorScheme
		let randomHue: Double
		let randomSaturation: Double
		let randomBrightness: Double
		let randomPoints: [CGPoint]
		
		init(seed: UInt64 = UInt64.random(in:0..<UInt64.max)) {
			var rng = SeededGenerator(seed: seed)
			randomHue = Double.random(in: 0..<1, using: &rng)
			randomSaturation = Double.random(in: 0.7..<1, using: &rng)
			randomBrightness = Double.random(in: 0.8..<1, using: &rng)
			
			randomPoints = (0..<4).map { _ in
				CGPoint(x: CGFloat.random(in: 0...1, using: &rng), y: CGFloat.random(in: 0...1, using: &rng))
			}
		}
		init(hue: Double, seed: UInt64) {
			randomHue = hue
			randomSaturation = Double.random(in: 0.7..<1)
			randomBrightness = Double.random(in: 0.8..<1)
			var rng = SeededGenerator(seed: seed)
			randomPoints = (0..<4).map { _ in
				CGPoint(x: CGFloat.random(in: 0...1, using: &rng), y: CGFloat.random(in: 0...1, using: &rng))
			}
		}
		
		func createPath(in geometry: GeometryProxy) -> Path {
			var path = Path()
			path.move(to: geometry.size * randomPoints[0])
			for point in randomPoints.dropFirst() {
				path.addLine(to: geometry.size * point)
			}
			path.closeSubpath()
			return path
		}
		
		func pattern(for index: Int, in geometry: GeometryProxy) -> some View {
				let interleavedIndex = (index % 2 == 0) ? index / 2 : 7 - index / 2
				let angle = Angle(degrees: Double(interleavedIndex) * 45)
				
				let adjustedBrightness = colorScheme == .light
					? randomBrightness * (0.7 + Double(interleavedIndex) / 8)
					: randomBrightness * (1 - Double(interleavedIndex) / 8)
				
				let adjustedSaturation = colorScheme == .light
					? randomSaturation * (0.5 + Double(interleavedIndex) / 16)
					: randomSaturation * (1 - Double(interleavedIndex) / 8)
				
				let baseOpacity = 0.3 + 0.1 * Double(interleavedIndex)
				let adjustedOpacity = colorScheme == .light
					? baseOpacity * 0.7 + 0.1
					: baseOpacity
				
				return createPath(in: geometry)
					.foregroundColor(
						Color(hue: randomHue,
							  saturation: adjustedSaturation,
							  brightness: adjustedBrightness)
					)
					.opacity(adjustedOpacity)
					.rotationEffect(angle, anchor: .center)
			}
			
			var body: some View {
				GeometryReader { geometry in
					ZStack {
						ForEach(0..<8) { index in
							pattern(for: index, in: geometry)
						}
					}
				}
			}
	}
}
