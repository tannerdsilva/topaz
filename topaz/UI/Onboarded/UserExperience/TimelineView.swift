//
//  TimelineView.swift
//  topaz
//
//  Created by Tanner Silva on 3/21/23.
//

import Foundation
import SwiftUI

struct TimelineModel:Identifiable {
	var id:String {
		get {
			return event.keySignature.base64EncodedString()
		}
	}
	let keysig:String
	var event:nostr.Event
	var profile:nostr.Profile?
	
	init(event:nostr.Event, profile:nostr.Profile?) {
		self.event = event
		self.profile = profile
		self.keysig = event.keySignature.base64EncodedString()
	}
}

struct EventDetailView: View {
	let event: nostr.Event
	let profile: nostr.Profile?

	var body: some View {
		VStack {
			Text("Event Detail View")
			// Add more content as needed
		}
	}
}

struct TimelineView: View {
	let ue: UE
	@State private var timeline = [TimelineModel]()
	@State private var isLoading: Bool = false
	@State private var lastEventDate: Date? = nil
	@State private var lastEventUID: String? = nil

	var body: some View {
		NavigationStack {
			ScrollView {
				LazyVStack {
					ForEach(timeline) { item in
						NavigationLink(destination: EventDetailView(event: item.event, profile: item.profile)) {
							EventViewCell(event: item.event, profile: item.profile)
						}

						if timeline.last?.id == item.id && !isLoading {
							Divider()
							ProgressView() // Loading indicator
								.onAppear {
									loadMoreData()
								}
						}
					}
				}
			}
			.onAppear {
				loadMoreData()
			}
		}
	}
	func loadMoreData() {
		isLoading = true

		let newEventsAndProfiles = ue.getHomeTimelineState()
		
		var newTimelineItems = [TimelineModel]()
		for newEvent in newEventsAndProfiles.0 {
			let getProf = newEventsAndProfiles.1[newEvent.pubkey]
			newTimelineItems.append(TimelineModel(event:newEvent, profile:getProf))
		}
		
		timeline.append(contentsOf: newTimelineItems)
		isLoading = false
		
		// Update the last event's date and UID for the next pagination request
		if let lastEvent = newEventsAndProfiles.0.last {
			lastEventDate = lastEvent.created
			lastEventUID = lastEvent.uid
		}
	}
}
