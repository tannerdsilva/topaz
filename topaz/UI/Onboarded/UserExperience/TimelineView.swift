//
//  TimelineView.swift
//  topaz
//
//  Created by Tanner Silva on 3/21/23.
//

import Foundation
import SwiftUI

struct TimelineView: View {
	let ue:UE
//	@State private var timeline = [TimelineModel]()
//	@State private var isLoading: Bool = false
//	@State private var lastEventDate: Date? = nil
//	@State private var lastEventUID: String? = nil

	var body: some View {
//		ScrollView {
//			LazyVStack(spacing: 10) {
//				ForEach(timeline) { item in
//					EventViewCell(event: item.event, profile: item.profile)
//
//					if timeline.last?.id == item.id && !isLoading {
//						Divider()
//						ProgressView() // Loading indicator
//							.onAppear {
//								loadMoreData()
//							}
//					}
//				}
//			}
//		}
//		.onAppear {
//			loadMoreData()
//		}
		Text("FOO")
	}
	
//	func loadMoreData() {
//		isLoading = true
//
//		// Example function signature for the database
//		fetchEventsAndProfiles(lastEventDate: lastEventDate, lastEventUID: lastEventUID, limit: 20) { newEventsAndProfiles in
//			let newTimelineItems = newEventsAndProfiles.map { (event, profile) -> TimelineModel in
//				return TimelineModel(id: UUID(), event: event, profile: profile)
//			}
//			
//			timeline.append(contentsOf: newTimelineItems)
//			isLoading = false
//			
//			// Update the last event's date and UID for the next pagination request
//			if let lastEvent = newEventsAndProfiles.last?.0 {
//				lastEventDate = lastEvent.date
//				lastEventUID = lastEvent.uid
//			}
//		}
//	}
}
