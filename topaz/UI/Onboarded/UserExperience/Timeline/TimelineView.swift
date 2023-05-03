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
		@Published var sessionID = UUID().uuidString
		private let logger = Topaz.makeDefaultLogger(label:"vm-timeline")
		@MainActor private var shownPostIndexRange: Range<Int>?
		@MainActor @Published var posts: [TimelineModel] = []
		@MainActor private var postUIDs: Set<nostr.Event.UID> = []
		let dbux:DBUX
		private let batchSize: UInt16
		private let showReplies:Bool
		private var postTrimmingTask:Task<Void, Swift.Error>? = nil
		
		private var showingEvents = Set<nostr.Event>()
		
		func updateAnchorDate(to newAnchorDate: DBUX.DatedNostrEventUID) {
			dbux.contextEngine.timelineAnchor = newAnchorDate
		}
		
		init(dbux: DBUX, batchSize: UInt16 = 48, showReplies:Bool) {
			self.dbux = dbux
			self.batchSize = batchSize
			self.showReplies = showReplies
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

		private func sortPosts(_ posts: [TimelineModel]) -> [TimelineModel] {
			return posts.sorted { $0.event.created > $1.event.created }
		}
		
		func findClosestEvent(to target: DBUX.DatedNostrEventUID?) -> nostr.Event? {
			guard let target = target else { return nil }
			for event in self.posts {
				let makeTarget = DBUX.DatedNostrEventUID(date:target.date, obj:target.uid)
				if target <= makeTarget {
					return event.event
				}
			}
			return nil
		}
		
		func addEventsToTimeline(newPosts: [TimelineModel]) {
			// Filter out events that are already in the timeline
			let filteredPosts = newPosts.filter { !postUIDs.contains($0.event.uid) }

			// Add the new event UIDs to the postUIDs set
			postUIDs.formUnion(filteredPosts.map { $0.event.uid })

			// Combine the current posts with the new posts and sort them by created date
			let updatedPosts = sortPosts(posts + filteredPosts)

			// Update the posts array
			self.posts = updatedPosts
		}

		
		func loadPosts(direction: ScrollDirection) async throws {
			var newPosts:[UI.TimelineModel]
			if posts.count > 0 {
				switch direction {
				case .up:
					let getAnchor = DBUX.DatedNostrEventUID(date:posts.first?.event.created ?? DBUX.Date(), obj:posts.first?.event.uid ?? nostr.Event.UID.nullUID())
					newPosts = try await loadPostsFromDatabase(anchorDate:getAnchor, direction: direction, limit: batchSize, showReplies: true)
				case .down:
					let getAnchor = DBUX.DatedNostrEventUID(date:posts.last?.event.created ?? DBUX.Date(), obj:posts.last?.event.uid ?? nostr.Event.UID.nullUID())
					newPosts = try await loadPostsFromDatabase(anchorDate:getAnchor, direction: direction, limit: batchSize, showReplies: true)
				}
			} else {
				let getAnchor = dbux.contextEngine.timelineAnchor ?? DBUX.DatedNostrEventUID(date:DBUX.Date(), obj:nostr.Event.UID.nullUID())
				newPosts = try await loadPostsFromDatabase(anchorDate:getAnchor, direction: direction, limit: batchSize, showReplies: true)
			}
			
			if showReplies == true {
				newPosts = newPosts.filter { $0.event.isReply() == false }
			}
			self.logger.info("adding \(newPosts.count) new posts.", metadata:["direction":"\(direction)"])
			let filteredPosts = newPosts.filter { !postUIDs.contains($0.event.uid) }

			postUIDs.formUnion(filteredPosts.map { $0.event.uid })
			// Use a temporary variable to store the updated posts
			var updatedPosts: [TimelineModel] = []

			if direction == .up {
				updatedPosts = sortPosts(filteredPosts + posts)
			} else {
				updatedPosts = sortPosts(posts + filteredPosts)
			}
			
			// Trimming excess posts if needed
			self.posts = updatedPosts
		}

		
		private func loadPostsFromDatabase(anchorDate: DBUX.DatedNostrEventUID?, direction: ScrollDirection, limit: UInt16, showReplies: Bool) async throws -> [TimelineModel] {
			do {
				let (events, profiles) = try await dbux.getHomeTimelineState(anchor: anchorDate, direction: direction, limit:limit)
				return events.map { event in
					let profile = profiles[event.pubkey]
					return TimelineModel(event: event, profile: profile)
				}
			} catch {
				print("Error loading posts from database: \(error)")
				return []
			}
		}
		
		func beganShowing(_ event: nostr.Event) {
			showingEvents.update(with: event)
			logger.info("now showing event id \(event.uid.description.prefix(5))", metadata: ["total_showing": "\(showingEvents.count)"])

			// Find the indices of the shown events in the posts array
			let shownEventIndices = showingEvents.compactMap { event in
				posts.firstIndex(where: { $0.event.uid == event.uid })
			}

			// Check if there are indices in shownEventIndices
			if !shownEventIndices.isEmpty {
				// Update the shownPostIndexRange based on the contents of showingEvents
				let minIndex = shownEventIndices.min()!
				let maxIndex = shownEventIndices.max()!

				shownPostIndexRange = minIndex..<maxIndex + 1
				let getObj = self.posts[minIndex].event
				let anchor = DBUX.DatedNostrEventUID(date:event.created, obj:event.uid)
				self.dbux.contextEngine.timelineAnchor = anchor
				// Call the updateContentIfNeeded() method
				updateContentIfNeeded()
			}
		}
		
		private func trimPostsIfNeeded() {
			guard let range = shownPostIndexRange else { return }

			let threshold = Int(batchSize)

			if range.lowerBound > threshold {
				// Trim posts from the top
				let postsToRemove = range.lowerBound - threshold
				if postsToRemove > 0 {
					posts.removeFirst(postsToRemove)
					postUIDs.subtract(posts.prefix(postsToRemove).map { $0.event.uid })
				}
			}

			if posts.count - range.upperBound > threshold {
				// Trim posts from the bottom
				let postsToRemove = posts.count - range.upperBound - threshold
				if postsToRemove > 0 {
					posts.removeLast(postsToRemove)
					postUIDs.subtract(posts.suffix(postsToRemove).map { $0.event.uid })
				}
			}
		}
		private func updateContentIfNeeded() {
			guard let range = shownPostIndexRange else { return }
			// Determine if we should load more content based on the shown post index range
			let threshold = Int(batchSize) / 2

			if range.lowerBound <= threshold {
				// Load more content when the user is close to the top
				Task { [weak self] in
					try await self?.loadPosts(direction: .up)
				}
			}
			if posts.count - range.upperBound <= threshold {
				// Load more content when the user is close to the bottom
				Task { [weak self] in
					try await self?.loadPosts(direction: .down)
				}
			}
		}

		
		func stoppedShowing(_ event: nostr.Event) {
			showingEvents.remove(event)
			logger.info("no longer showing event id \(event.uid.description.prefix(5))", metadata: ["total_showing": "\(showingEvents.count)"])
		}

		func startModel() {
			self.sessionID = UUID().uuidString
			Task.detached { [weak self, hol = dbux.eventsEngine.relaysEngine.holder] in
				await self?.onScroll(direction:.down)
				
				// begin consuming the events as they come off the relay engine
				for await curEvents in hol {
					guard let self = self else { return }
					let lastEvent = await self.posts.last?.event.created
					guard Task.isCancelled == false else { return }
					
					let followsTX = try self.dbux.eventsEngine.transact(readOnly:true)
					let myFollows = try self.dbux.eventsEngine.followsEngine.getFollows(pubkey:self.dbux.keypair.pubkey, tx:followsTX)
					try followsTX.commit()
					
					
					var buildEvents = Set<nostr.Event>()
					var buildKeys = Set<nostr.Key>()
					for curEv in curEvents {
						if curEv.1.kind == .text_note && myFollows.contains(curEv.1.pubkey) {
							if let hasLastEventDate = lastEvent {
								if hasLastEventDate < curEv.1.created {
									buildEvents.update(with:curEv.1)
									buildKeys.update(with:curEv.1.pubkey)
								}
							} else {
								buildEvents.update(with:curEv.1)
								buildKeys.update(with:curEv.1.pubkey)
							}
						}
					}
					
					let profilesTX = try self.dbux.eventsEngine.transact(readOnly:true)
					let getProfiles = try self.dbux.eventsEngine.profilesEngine.getPublicKeys(publicKeys:buildKeys, tx: profilesTX)
					try profilesTX.commit()
					
					var buildOutput = [UI.TimelineModel]()
					for curItem in buildEvents {
						buildOutput.append(UI.TimelineModel(event: curItem, profile:getProfiles[curItem.pubkey]))
					}
					await self.addEventsToTimeline(newPosts:buildOutput)
				}
			}
		}
		func stopModel() {
			self.sessionID = "CLEARED"
			posts.removeAll()
			postUIDs.removeAll()
			showingEvents.removeAll()
			shownPostIndexRange = nil
		}
	}
	
	struct TimelineView: View {
		let dbux:DBUX
		@ObservedObject var postsOnlyModel: TimelineViewModel
		@ObservedObject var withRepliesModel: TimelineViewModel
		@ObservedObject var context:DBUX.ContextEngine
		
		@State var isShowing = false
		
		init(dbux:DBUX, postsOnlyModel:TimelineViewModel, withRepliesModel:TimelineViewModel) {
			self.dbux = dbux
			self.postsOnlyModel = postsOnlyModel
			self.withRepliesModel = withRepliesModel
			self.context = dbux.contextEngine
			
		}
		
		var body: some View {
			if (context.timelineRepliesToggleEnabled) {
				self.postsOnlyTimeline
			} else {
				self.withRepliesTimeine
			}
		}
		
		@ViewBuilder
		var noEventsView: some View {
			Text("No events to display.")
				.font(.title)
				.foregroundColor(.secondary)
				.padding()
		}
		
		@ViewBuilder
		var postsOnlyTimeline: some View {
			ScrollViewReader { scrollViewProxy in
				ScrollView {
					LazyVStack {
						ForEach(postsOnlyModel.posts) { item in
							//							if postsOnlyModel.posts.first?.id == item.id {
							//								onAppearLoadingIndicator(model: postsOnlyModel, direction: .up, item: item).id("LOADING_TOP_IND")
							//							}
							
							NavigationLink(destination: EventDetailView(event: item.event, profile: item.profile)) {
								EventViewCell(dbux: self.dbux, event: item.event, profile: item.profile).onAppear {
									postsOnlyModel.beganShowing(item.event)
								}.onDisappear {
									postsOnlyModel.stoppedShowing(item.event)
								}
							}
							
							//							if postsOnlyModel.posts.last?.id == item.id {
							//								onAppearLoadingIndicator(model: postsOnlyModel, direction: .down, item: item).id("LOADING_BOTTOM_IND")
							//							}
						}
					}.id("__TL_PO_\(dbux.keypair.pubkey.description)")
				}.onAppear {
					postsOnlyModel.startModel()
				}.onDisappear {
					postsOnlyModel.stopModel()
				}
				
			}
		}
		
		@ViewBuilder
		var withRepliesTimeine: some View {
			ScrollViewReader { scrollViewProxy in
				ScrollView {
					LazyVStack {
						ForEach(withRepliesModel.posts) { item in
							//							if withRepliesModel.posts.first?.id == item.id {
							//								onAppearLoadingIndicator(model: withRepliesModel, direction: .up, item: item).id("LOADING_TOP_IND")
							//							}
							
							NavigationLink(destination: EventDetailView(event: item.event, profile: item.profile)) {
								EventViewCell(dbux: dbux, event: item.event, profile: item.profile).onAppear {
									withRepliesModel.beganShowing(item.event)
								}.onDisappear {
									withRepliesModel.stoppedShowing(item.event)
								}
							}
							
							//							if withRepliesModel.posts.last?.id == item.id {
							//								onAppearLoadingIndicator(model: withRepliesModel, direction: .down, item: item).id("LOADING_BOTTOM_IND")
							//							}
						}
					}.id("__TL_WR_\(dbux.keypair.pubkey.description)")
				}.onAppear {
					withRepliesModel.startModel()
				}.onDisappear {
					withRepliesModel.stopModel()
				}
			}
		}
	}
}
