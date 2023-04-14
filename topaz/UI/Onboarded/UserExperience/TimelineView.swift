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
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				profileBanner
				eventInfo
				eventContent
				Spacer()
			}
			.padding()
		}
	}

	private var profileBanner: some View {
		ZStack {
//			if let bannerURL = profile?.banner, let url = URL(string: bannerURL) {
//				AsyncImage(url: url, scale: 1.0) { image in
//					image
//						.resizable()
//						.scaledToFill()
//				} placeholder: {
//					RoundedRectangle(cornerRadius: 10)
//						.fill(Color.gray)
//				}
//			} else {
				RoundedRectangle(cornerRadius: 10)
					.fill(Color.gray)
//			}
		}
		.frame(height: 200)
		.cornerRadius(10)
		.overlay(
			VStack(alignment: .leading, spacing: 10) {
				if let displayName = profile?.display_name {
					Text(displayName)
						.font(.largeTitle)
						.fontWeight(.bold)
						.foregroundColor(.white)
				}
				if let about = profile?.about {
					Text(about)
						.font(.subheadline)
						.fontWeight(.medium)
						.foregroundColor(.white)
				}
			}
			.padding(),
			alignment: .bottomLeading
		)
	}

/*
 private var eventInfo: some View {
		 VStack(alignment: .leading, spacing: 8) {
			 HStack {
				 Text("Created on")
					 .font(.headline)
				 Spacer()
				 Text("\(event.created, formatter: dateFormatter)")
					 .font(.subheadline)
			 }

			 HStack {
				 Text("Event ID")
					 .font(.headline)
				 Spacer()
				 Text(event.uid)
					 .font(.subheadline)
					 .lineLimit(1)
			 }

			 if let boosted_by = event.boosted_by {
				 HStack {
					 Text("Boosted by")
						 .font(.headline)
					 Spacer()
					 Text(boosted_by)
						 .font(.subheadline)
						 .lineLimit(1)
				 }
			 }

			 Text("Tags")
				 .font(.headline)
			 ForEach(event.tags) { tag in
				 VStack(alignment: .leading) {
					 Text(tag.kind.rawValue.capitalized)
						 .font(.subheadline)
						 .fontWeight(.bold)
					 ForEach(tag.info, id: \.self) { tagInfo in
						 Text(tagInfo)
							 .font(.body)
							 .padding(.leading, 10)
					 }
				 }
				 .padding(.bottom, 5)
			 }
		 }
	 }
 */
	private var eventInfo: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("Created on")
					.font(.headline)
				Spacer()
				Text("\(event.created, formatter: dateFormatter)")
					.font(.subheadline)
			}

			HStack {
				Text("Event ID (\(event.uid.description.count))")
					.font(.headline)
				Spacer()
				Text(event.uid.description)
					.font(.subheadline)
					.lineLimit(1)
			}

			if let boosted_by = event.boosted_by {
				HStack {
					Text("Boosted by")
						.font(.headline)
					Spacer()
					Text(boosted_by)
						.font(.subheadline)
						.lineLimit(1)
				}
			}
		}
	}

	private var eventContent: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Event Content")
				.font(.title)
				.fontWeight(.bold)
			Text(event.content)
				.font(.body)
				.padding(.all, 10)
				.background(Color.gray.opacity(0.1))
				.cornerRadius(8)
		}
	}

	private var dateFormatter: DateFormatter {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .short
		return formatter
	}
}

struct TimelineView: View {
	let ue: UE
	@State private var timeline = [TimelineModel]()
	@State private var isLoading: Bool = false
	@State private var lastEventDate: Date? = nil
	@State private var lastEventUID: nostr.Event.UID? = nil
	
	// The maximum number of timeline items to keep in memory
	let maxItemsInMemory = 20

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
			.onDisappear {
				trimTimeline()
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
	
	func trimTimeline() {
		if timeline.count > maxItemsInMemory {
			timeline = Array(timeline.suffix(maxItemsInMemory))
		}
	}
}
