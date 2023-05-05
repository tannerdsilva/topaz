//
//  ConnectionStatusWidget.swift
//  topaz
//
//  Created by Tanner Silva on 4/16/23.
//

import Foundation
import SwiftUI

extension UI.Relays {
	struct ConnectionStatusWidget: View {
		
		let dbux:DBUX
		@ObservedObject var relays:DBUX.RelaysEngine
		@State private var isTextVisible = false
		@State var showModal = false
		
		var body: some View {
			GeometryReader { geometry in
				let circleSize: CGFloat = 6
				let spacing: CGFloat = 4
				let succ = relays.userRelayConnectionStates.sorted(by: { $0.key < $1.key }).compactMap({ $0.value })
				let connCount = succ.filter { $0 == .connected }
				
				VStack {
					ProgressRingShape(progress: Double(connCount.count) / Double(succ.count))
							.stroke(Color.green, lineWidth: 4)
							.frame(width: 22, height: 22)

					if isTextVisible {
						Text("\(connCount.count)/\(succ.count)")
							.font(.system(size: 12))
							.foregroundColor(.white)
							.transition(.opacity)
					}
				}
				.frame(width: geometry.size.width, height: geometry.size.height).sheet(isPresented: $showModal) {
					AllConnectionsScreen(dbux: dbux, relayDB: relays)
				}
			}
			.frame(width: 45, height: 30)
			.onTapGesture {
				showModal.toggle()
				if isTextVisible {
					Task.detached {
						try await Task.sleep(nanoseconds:5_000_000_000)
						await MainActor.run { () -> Void in
							withAnimation(.easeInOut(duration:0.25)) {
								isTextVisible = true
							}
						}
					}
				}
			}
		}
	}
	
	struct SyncStatusWidget: View {
		let dbux: DBUX
		@ObservedObject var relays: DBUX.RelaysEngine
		@State private var isTextVisible = false
		@State var showModal = false
		
		var body: some View {
			GeometryReader { geometry in
				let circleSize: CGFloat = 6
				let spacing: CGFloat = 4

				// Get the relaySyncStates and calculate the progress
				let relaySyncStates = relays.relaySyncStates
				let totalCount = relaySyncStates.values.reduce(0) { sum, dict in
					sum + dict.count
				}
				let trueCount = relaySyncStates.values.reduce(0) { sum, dict in
					sum + dict.values.filter { $0 }.count
				}
				let progress = totalCount > 0 ? Double(trueCount) / Double(totalCount) : 0

				VStack {
					ProgressRingShape(progress: progress)
						.stroke(Color.cyan, lineWidth: 4)
						.frame(width: 22, height: 22)

					if isTextVisible {
						Text("\(trueCount)/\(totalCount)")
							.font(.system(size: 12))
							.foregroundColor(.white)
							.transition(.opacity)
					}
				}
				.frame(width: geometry.size.width, height: geometry.size.height).sheet(isPresented: $showModal) {
					AllConnectionsScreen(dbux: dbux, relayDB: relays)
				}
			}
			.frame(width: 45, height: 30)
			.onTapGesture {
				showModal.toggle()
				if isTextVisible {
					Task.detached {
						try await Task.sleep(nanoseconds:5_000_000_000)
						await MainActor.run { () -> Void in
							withAnimation(.easeInOut(duration:0.25)) {
								isTextVisible = true
							}
						}
					}
				}
			}
		}
	}

}

extension UI.Relays {
	struct ProgressRingShape: Shape {
		let progress: Double
		
		func path(in rect: CGRect) -> Path {
			var path = Path()
			path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
						radius: rect.width / 2,
						startAngle: .degrees(-90),
						endAngle: .degrees(-90 + 360 * progress),
						clockwise: false)
			return path
		}
	}
}

// dot layout mode
extension UI.Relays.ConnectionStatusWidget {
	
	// all the dots are laid out in this view
	struct DotsLayout: View {
		
		// this is a single "dot" that represents the view for a single connection
		struct ConnectionDot: View {
			
			// a custom triangle shape to represent "down" connections
			struct Triangle: Shape {
				func path(in rect: CGRect) -> Path {
					var path = Path()

					path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
					path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
					path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
					path.closeSubpath()

					return path
				}
			}

			// a generic package for any path
			struct AnyShape: Shape {
				private let pathBuilder: (CGRect) -> Path

				init<S: Shape>(_ wrapped: S) {
					pathBuilder = { rect in
						return wrapped.path(in: rect)
					}
				}

				func path(in rect: CGRect) -> Path {
					return pathBuilder(rect)
				}
			}
			
			let state: RelayConnection.State

			var body: some View {
				connectionShape(state: state)
					.foregroundColor(colorForConnectionState(state))
			}

			func connectionShape(state: RelayConnection.State) -> some Shape {
				switch state {
				case .disconnected:
					return AnyShape(Triangle())
				case .connecting:
					return AnyShape(Rectangle())
				case .connected:
					return AnyShape(Circle())
				}
			}

			func colorForConnectionState(_ state: RelayConnection.State) -> Color {
				switch state {
				case .disconnected:
					return Color.red
				case .connecting:
					return Color.yellow
				case .connected:
					return Color.green
				}
			}
		}

		let spacing: CGFloat
		let shapeSize: CGFloat
		let status: [RelayConnection.State]

		var body: some View {
			GeometryReader { geometry in
				let numberOfColumns = Int((geometry.size.width - spacing) / (shapeSize + spacing))
				let numberOfRows = Int((geometry.size.height - spacing) / (shapeSize + spacing))
				let columns = Array(repeating: GridItem(.fixed(shapeSize), spacing: spacing), count: numberOfColumns)

				let horizontalPadding = (geometry.size.width - CGFloat(min(numberOfColumns, status.count)) * (shapeSize + spacing) + spacing) / 2
				let usedRows = max(1, Int(ceil(Double(status.count) / Double(numberOfColumns))))
				let verticalPadding = (geometry.size.height - CGFloat(usedRows) * (shapeSize + spacing) + spacing) / 2

				LazyVGrid(columns: columns, spacing: spacing) {
					ForEach(status.indices, id: \.self) { index in
						ConnectionDot(state: status[index])
							.frame(width: shapeSize, height: shapeSize)
					}
				}
				.padding(.horizontal, horizontalPadding)
				.padding(.vertical, verticalPadding)
			}
		}
		
		static func maxShapesInFrame(maxWidth: CGFloat, maxHeight: CGFloat, shapeSize: CGFloat, spacing: CGFloat) -> Int {
			let numberOfColumns = Int((maxWidth - spacing) / (shapeSize + spacing))
			let numberOfRows = Int((maxHeight - spacing) / (shapeSize + spacing))
			return numberOfColumns * numberOfRows
		}
	}
}
