//
//  TimelineView.swift
//  topaz
//
//  Created by Tanner Silva on 03-09-23.
//

import SwiftUI

enum TimelineAction {
	case chillin
	case navigating
}

struct TimelineView: View {
	@Environment(\.colorScheme) var colorScheme

	@ObservedObject var ue:UE
	
	var body: some View {
		MainContent
	}
	
	var realtime_bar_opacity: Double {
		colorScheme == .dark ? 0.2 : 0.1
	}
	
	var MainContent: some View {
		ScrollViewReader { scroller in
			ScrollView {
				Color.white.opacity(0)
					.id("startblock")
					.frame(height: 1)
				InnerTimelineView(ue:ue)
					.background(GeometryReader { proxy -> Color in
//						DispatchQueue.main.async {
//							handle_scroll_queue(proxy, queue: [])
//						}
						return Color.clear
					})
			}
			.buttonStyle(BorderlessButtonStyle())
			.coordinateSpace(name: "scroll")
		}
	}
}

protocol ScrollQueue {
	var should_queue: Bool { get }
	func set_should_queue(_ val: Bool)
}
	
func handle_scroll_queue(_ proxy: GeometryProxy, queue: ScrollQueue) {
	let offset = -proxy.frame(in: .named("scroll")).origin.y
	guard offset >= 0 else {
		return
	}
	let val = offset > 0
	if queue.should_queue != val {
		queue.set_should_queue(val)
	}
}
