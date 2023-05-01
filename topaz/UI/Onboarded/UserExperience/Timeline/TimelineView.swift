//
//  TimelineView.swift
//  topaz
//
//  Created by Tanner Silva on 3/21/23.
//

import Foundation
import SwiftUI

extension UI {
	struct TimelineModel:Identifiable, Hashable {
		static func == (lhs: UI.TimelineModel, rhs: UI.TimelineModel) -> Bool {
			return lhs.event.uid == rhs.event.uid
		}
		
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
		
		public func hash(into hasher:inout Hasher) {
			hasher.combine(event.uid)
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
		@MainActor @Published var posts: [TimelineModel] = [] {
			didSet {
				
			}
		}
		@MainActor private var postUIDs: Set<nostr.Event.UID> = []
		let dbux:DBUX
		@Published private(set) var anchorDate: DBUX.DatedNostrEventUID?
		private let batchSize: UInt16
		private var showReplies:Bool = false
		private var postTrimmingTask:Task<Void, Swift.Error>? = nil
		
		func updateAnchorDate(to newAnchorDate: DBUX.DatedNostrEventUID) {
			anchorDate = newAnchorDate
		}
		
		init(dbux: DBUX, anchorDate: DBUX.DatedNostrEventUID? = nil, batchSize: UInt16 = 48) {
			self.dbux = dbux
			self.anchorDate = anchorDate
			self.batchSize = batchSize
			Task { [weak self] in
				try await self?.loadPosts(direction: .down)
			}
		}
		
		enum ScrollDirection {
			case up
			case down
		}
		
		func onScroll(direction: ScrollDirection) {
			Task {
				try await loadPosts(direction: direction)
			}
		}
		
		private func trimPosts(direction:ScrollDirection) {
			if postTrimmingTask != nil {
				postTrimmingTask?.cancel()
			}
			postTrimmingTask = Task.detached(priority:.background) { @MainActor [weak self] in
				guard Task.isCancelled == false, let self = self else { return }
				if self.posts.count > self.batchSize * 4 {
					if direction == .up {
						self.posts.removeLast(self.posts.count)
					} else {
						self.posts.removeFirst(self.posts.count)
					}
				}
				self.postTrimmingTask = nil
			}
		}

		private func sortPosts(_ posts: [TimelineModel]) -> [TimelineModel] {
			return posts.sorted { $0.event.created > $1.event.created }
		}
		
		func loadPosts(direction: ScrollDirection) async throws {
			let newPosts = try await loadPostsFromDatabase(anchorDate: anchorDate, direction: direction, limit: batchSize, showReplies: true)
			let filteredPosts = newPosts.filter { !postUIDs.contains($0.event.uid) }

			postUIDs.formUnion(filteredPosts.map { $0.event.uid })
			print("LOADED \(newPosts.count) NEW EVENTS BRO: \(newPosts.compactMap({ $0.event.uid.description }).sorted(by: { $0 < $1 }))")
			// Use a temporary variable to store the updated posts
			var updatedPosts: [TimelineModel] = []

			if direction == .up {
				updatedPosts = sortPosts(filteredPosts + posts)
			} else {
				updatedPosts = sortPosts(posts + filteredPosts)
			}
			
			// Trimming excess posts if needed
			self.posts = updatedPosts
			await self.trimPosts(direction:direction)
		}

		
		private func loadPostsFromDatabase(anchorDate: DBUX.DatedNostrEventUID?, direction: ScrollDirection, limit: UInt16, showReplies: Bool) async throws -> [TimelineModel] {
			do {
				let (events, profiles) = try await dbux.getHomeTimelineState(anchor: anchorDate, direction: direction, limit:limit)
				print("LOADED \(events.count) events form databsae")
				return events.map { event in
					let profile = profiles[event.pubkey]
					return TimelineModel(event: event, profile: profile)
				}
			} catch {
				print("Error loading posts from database: \(error)")
				return []
			}
		}
	}

	
	struct TimelineView: View {
		@ObservedObject var viewModel: TimelineViewModel
		@Binding var showReplies: Bool
		
		var body: some View {
			ScrollViewReader { scrollViewProxy in
				ScrollView {
					LazyVStack {
						if viewModel.posts.isEmpty {
							noEventsView
						} else {
							timelineView
						}
					}
				}
				.onAppear {
					viewModel.onScroll(direction: .down)
				}
				// Scroll to the anchor date item when the list is updated
				.onChange(of: viewModel.posts.count) { _ in
					if let anchorDateUID = viewModel.anchorDate {
						scrollViewProxy.scrollTo(anchorDateUID, anchor: .center)
					}
				}
			}
		}
		
		@ViewBuilder
		var noEventsView: some View {
			Text("No events to display.")
				.font(.title)
				.foregroundColor(.secondary)
				.padding()
		}
		
		func postsBasedOnToggle() -> [UI.TimelineModel] {
			return showReplies ? viewModel.posts : viewModel.posts.filter({ !$0.event.isReply() })
		}
		
		@ViewBuilder
		var timelineView: some View {
			let filteredPosts = postsBasedOnToggle()
			
			ForEach(filteredPosts) { item in
				if filteredPosts.first?.id == item.id {
					onAppearLoadingIndicator(direction: .up).id("LOADING_TOP_IND")
				}

				NavigationLink(destination: EventDetailView(event: item.event, profile: item.profile)) {
					EventViewCell(dbux: viewModel.dbux, event: item.event, profile: item.profile)
						.onAppear {
							viewModel.updateAnchorDate(to: DBUX.DatedNostrEventUID(date: item.event.created, obj: item.event.uid))
						}
				}

				if filteredPosts.last?.id == item.id {
					onAppearLoadingIndicator(direction: .down).id("LOADING_BOTTOM_IND")
				}
			}.id(filteredPosts.count)
		}
		
		@ViewBuilder
		func onAppearLoadingIndicator(direction: TimelineViewModel.ScrollDirection) -> some View {
			ProgressView()
				.onAppear {
					viewModel.onScroll(direction: direction)
				}
		}
	}
}
