//
//  TimelineView.swift
//  topaz
//
//  Created by Tanner Silva on 3/21/23.
//

import Foundation
import SwiftUI

extension UI {
	struct TimelineModel:Identifiable {
		var id:nostr.Event.UID {
			get {
				return event.uid
			}
		}
		var event:nostr.Event
		var profile:nostr.Profile?
		
		init(event:nostr.Event, profile:nostr.Profile?) {
			self.event = event
			self.profile = profile
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
				RoundedRectangle(cornerRadius: 10)
					.fill(Color.gray)
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
					Text("\(event.created.exportDate(), formatter: dateFormatter)")
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

	@MainActor
	class TimelineViewModel: ObservableObject {
		let dbux: DBUX
		@Published private(set) var timeline: [TimelineModel] = []
		@Published private(set) var isLoading: Bool = false
		private let maxItemsInMemory = 20
		private let loadingBuffer = 5
		private var lastLoadDirection: DBUX.EventsEngine.TimelineEngine.ReadDirection?
			
		init(dbux: DBUX) {
			self.dbux = dbux
		}
		
		func updateAnchorPoint(_ currentItem: TimelineModel) {
			let anchor = DBUX.DatedNostrEventUID(date: currentItem.event.created, obj: currentItem.event.uid)
			dbux.contextEngine.timelineAnchor = anchor
				
				let index = timeline.firstIndex(where: { $0.id == currentItem.id }) ?? 0
				if index < loadingBuffer && lastLoadDirection != .forward {
					Task {
						lastLoadDirection = .forward
						await loadMoreData(direction: .forward)
					}
				} else if index > timeline.count - loadingBuffer - 1 && lastLoadDirection != .backward {
					Task {
						lastLoadDirection = .backward
						await loadMoreData(direction: .backward)
					}
				}
			}

		
		func loadMoreData(direction: DBUX.EventsEngine.TimelineEngine.ReadDirection = .backward) {
			isLoading = true
			do {
				let anchor: DBUX.DatedNostrEventUID?
				switch direction {
				case .forward:
					anchor = timeline.first.map { DBUX.DatedNostrEventUID(date: $0.event.created, obj: $0.event.uid) }
				case .backward:
					anchor = timeline.last.map { DBUX.DatedNostrEventUID(date: $0.event.created, obj: $0.event.uid) }
				}
				let newEventsAndProfiles = try dbux.getHomeTimelineState(anchor: anchor, direction: direction)
				var newTimelineItems = [TimelineModel]()
				for newEvent in newEventsAndProfiles.0 {
					let getProf = newEventsAndProfiles.1[newEvent.pubkey]
					newTimelineItems.append(TimelineModel(event: newEvent, profile: getProf))
				}

				// Reverse the order of newTimelineItems
				newTimelineItems.reverse()

				switch direction {
				case .forward:
					timeline = newTimelineItems + timeline
				case .backward:
					timeline.append(contentsOf: newTimelineItems)
				}
				
				isLoading = false
			} catch {}
		}
		
		func trimTimeline() {
			if timeline.count > maxItemsInMemory {
				timeline = Array(timeline.suffix(maxItemsInMemory))
			}
		}
	}


	struct TimelineView: View {
		@ObservedObject var viewModel: TimelineViewModel
		let dbux: DBUX

		var body: some View {
			ScrollView {
				LazyVStack {
					if viewModel.timeline.isEmpty {
						Text("No events to display.")
							.font(.title)
							.foregroundColor(.secondary)
							.padding()
					} else {
						ForEach(viewModel.timeline) { item in
							if viewModel.timeline.first?.id == item.id && !viewModel.isLoading {
								ProgressView() // Loading indicator for forwards
									.onAppear {
										Task {
											viewModel.loadMoreData(direction: .forward)
										}
									}
							}

							NavigationLink(destination: EventDetailView(event: item.event, profile: item.profile)) {
								EventViewCell(dbux: dbux, event: item.event, profile: item.profile)
									.onAppear {
										viewModel.updateAnchorPoint(item)
									}
							}

							if viewModel.timeline.last?.id == item.id && !viewModel.isLoading {
								Divider()
								ProgressView() // Loading indicator for backwards
									.onAppear {
										Task {
											viewModel.loadMoreData(direction: .backward)
										}
									}
							}
						}
					}
				}
			}
			.onAppear {
				Task {
					viewModel.loadMoreData()
				}
			}
			.onDisappear {
				viewModel.trimTimeline()
			}
		}
	}
}
