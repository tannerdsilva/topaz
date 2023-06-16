//
//  ProfileDetailView.swift
//  topaz
//
//  Created by Tanner Silva on 3/29/23.
//

import Foundation
import SwiftUI

struct HeaderOffsetKey: PreferenceKey {
	static var defaultValue: CGFloat = 0
	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
		value = nextValue()
	}
}
struct ProfileDetailView: View {
	@Environment(\.presentationMode) var presentationMode
	let dbux:DBUX
	let pubkey:nostr.Key
	let profile:nostr.Profile
	let showBack:Bool

	@ObservedObject var profileEngine:DBUX.ProfilesEngine // Load the user profile data here

	var body: some View {
		if showBack {
			UpperProfileView(dbux:dbux, pubkey:pubkey, profile:profile).navigationBarBackButtonHidden(true).toolbar {
				ToolbarItem(placement: .navigationBarLeading) {
					CustomBackButton()
				}
			}.modifier(DragToDismiss(threshold:0.3))
		} else {
			UpperProfileView(dbux:dbux, pubkey:pubkey, profile:profile).navigationBarBackButtonHidden(true)
		}
	}
}

struct UpperProfileView: View {
	struct BannerVisualContentView: View {
		let dbux:DBUX
		let bannerURL: URL?

		var body: some View {
			if let url = bannerURL {
				UI.Images.AssetPipeline.AsyncImage(url: url, actor:dbux.storedImageActor) { image in
					image.resizable()
						.scaledToFill()
				} placeholder: {
					UI.AbstractView()
				}
			} else {
				UI.AbstractView()
			}
		}
	}
	
	struct ProfilePictureView: View {
		let dbux:DBUX
		let pictureURL: URL?

		var body: some View {
			Group {
				if let url = pictureURL {
					UI.Images.AssetPipeline.AsyncImage(url: url, actor:dbux.storedImageActor) { image in
						image.resizable()
							.aspectRatio(contentMode: .fill)
					} placeholder: {
						ProgressView()
					}
				} else {
					ProgressView()
				}
			}
			.frame(width: 50, height: 50)
			.clipShape(Circle())
		}
	}
	
	struct ProfileFullNameView: View {
		var displayName: String?
		var userName: String?
		var displayEmojis: Bool
		var isVerified: Bool = false
		var isPrimary: Bool

		var body: some View {
			HStack(spacing: 4) {
				let name = displayName ?? userName ?? "Unknown"
				Text(displayEmojis ? name : name.noEmoji)
					.font(isPrimary ? .headline : .subheadline)
					.foregroundColor(isPrimary ? Color.primary : .gray.opacity(0.6))
					.fontWeight(isPrimary ? .semibold : .regular)

				if isVerified && isPrimary {
					Image(systemName: "checkmark.circle.fill")
						.foregroundColor(.blue)
						.font(.system(size: 18))
				}
			}
		}
	}

	struct ProfileUsernameView: View {
		var userName: String?
		var isVerified: Bool = false
		var isPrimary: Bool

		var body: some View {
			HStack(spacing: 2) {
				Image(systemName: "at")
					.foregroundColor(isPrimary ? .gray : .gray.opacity(0.6))
					.font(.system(size: isPrimary ? 12 : 8))
					.opacity(0.5)

				let cleanUserName = (userName ?? "Unknown").noEmoji
				Text(cleanUserName)
					.font(isPrimary ? .headline : .subheadline)
					.foregroundColor(isPrimary ? Color.primary : .gray.opacity(0.6))
					.fontWeight(isPrimary ? .semibold : .regular)

				if isVerified && isPrimary {
					Image(systemName: "checkmark.circle.fill")
						.foregroundColor(.blue)
						.font(.system(size: 18))
				}
			}
		}
	}


	struct DisplayNameView: View {
		let dbux: DBUX
		var displayName: String?
		var userName: String?
		var isVerified: Bool
		@ObservedObject var contextEngine: DBUX.ContextEngine
		
		init(dbux: DBUX, displayName: String?, userName: String?, isVerified: Bool = false) {
			self.dbux = dbux
			contextEngine = dbux.contextEngine
			self.displayName = displayName
			self.userName = userName
			self.isVerified = isVerified
		}
		
		var body: some View {
			VStack(alignment: .leading, spacing: 2) {
						let appearanceSettings = contextEngine.userPreferences.appearanceSettings
						let namePriority = appearanceSettings.namePriorityPreference
						let displayEmojis = appearanceSettings.displayEmojisInNames

						if namePriority == .fullNamePreferred {
							ProfileFullNameView(displayName: displayName, userName: userName, displayEmojis: displayEmojis, isVerified: isVerified, isPrimary: true)
							if let username = userName {
								ProfileUsernameView(userName: username, isPrimary: false)
							}
						} else {
							ProfileUsernameView(userName: userName ?? "Unknown", isVerified: isVerified, isPrimary: true)
							if let fullname = displayName {
								ProfileFullNameView(displayName: fullname, displayEmojis: displayEmojis, isPrimary: false)
							}
						}
					}
			}
	}

	
	struct ProfileInfoView: View {
		let profile: nostr.Profile

		struct WebsiteLinkView: View {
			let website: String

			var body: some View {
				if let asActionableURL = URL(string: website) {
					Link("Website: \(website)", destination: asActionableURL)
				} else {
					Text("Website: \(website)")
				}
			}
		}

		var body: some View {
			VStack(alignment: .leading, spacing: 8) {
				if let about = profile.about {
					Text(about)
						.padding(.horizontal, 16)
				}

				if let website = profile.website {
					WebsiteLinkView(website: website)
						.padding(.horizontal, 16)
				}
			}
			.padding(.bottom, 16)
		}
	}
	
	struct BannerBackgroundWithGradientView:View {
		let dbux:DBUX
		let pubkey:nostr.Key
		let profile: nostr.Profile
		var body:some View {
			GeometryReader { innerGeometry in
				// can expand beyond safe area
				ZStack(alignment: .bottom) {
					BannerVisualContentView(dbux:dbux, bannerURL: profile.banner.flatMap { URL(string: $0) })
						.frame(width: innerGeometry.size.width, height: innerGeometry.size.height).clipped()
					
					LinearGradient(gradient: Gradient(colors: [
						Color.black.opacity(0),
						Color.black.opacity(0.10),
						Color.black.opacity(0.35),
						Color.black.opacity(0.55),
						Color.black.opacity(0.75),
						Color.black.opacity(0.92)
					]), startPoint: .top, endPoint: .bottom)
					.frame(width: innerGeometry.size.width, height: innerGeometry.size.height)
					.edgesIgnoringSafeArea(.top)
				}
			}
		}
	}
	
	
	class ProfileViewModel: ObservableObject {
		private let logger = Topaz.makeDefaultLogger(label:"vm-profile")
		@MainActor private var shownPostIndexRange: Range<Int>?
		@MainActor @Published var posts: [UI.TimelineModel] = []
		@MainActor private var postUIDs: Set<nostr.Event.UID> = []
		let dbux:DBUX
		let targetUser:nostr.Key
		private let batchSize: UInt16
		private let showReplies:Bool
		private var postTrimmingTask:Task<Void, Swift.Error>? = nil

		private var showingEvents = Set<nostr.Event>()

		@MainActor func updateAnchorDate(to newAnchorDate: DBUX.DatedNostrEventUID) {
			dbux.contextEngine.timelineAnchor = newAnchorDate
		}

		init(dbux: DBUX, batchSize: UInt16 = 48, showReplies:Bool, targetUser:nostr.Key) {
			self.dbux = dbux
			self.batchSize = batchSize
			self.showReplies = showReplies
			self.targetUser = targetUser
		}

		func onScroll() {
			Task {
				try await loadPosts()
			}
		}

		@MainActor private func sortPosts(_ posts: [UI.TimelineModel]) -> [UI.TimelineModel] {
			return posts.sorted { $0.event.created > $1.event.created }
		}

		@MainActor func findClosestEvent(to target: DBUX.DatedNostrEventUID?) -> nostr.Event? {
			guard let target = target else { return nil }
			for event in self.posts {
				let makeTarget = DBUX.DatedNostrEventUID(date:target.date, obj:target.uid)
				if target <= makeTarget {
					return event.event
				}
			}
			return nil
		}

		@MainActor func addEventsToTimeline(newPosts: [UI.TimelineModel]) {

			// Filter out events that are already in the timeline
			var filteredPosts = newPosts.filter { !postUIDs.contains($0.event.uid) }
			if self.showReplies == false {
				// remove the replies from the input
				filteredPosts = filteredPosts.filter { !$0.event.isReply() }
			}
			// Add the new event UIDs to the postUIDs set
			postUIDs.formUnion(filteredPosts.map { $0.event.uid })

			// Combine the current posts with the new posts and sort them by created date
			let updatedPosts = sortPosts(posts + filteredPosts)

			// Update the posts array
			self.posts = updatedPosts
		}


		@MainActor func loadPosts() async throws {
			let targetDate = self.posts.first?.event.created.exportDate() ?? Date()
			var buildFilter = nostr.Filter(kinds: [.text_note], pubkeys: [self.targetUser], since:targetDate, limit:50)
			let buildSub = nostr.Subscribe(sub_id:"_PROF_NOTES_\(self.targetUser.description)", filters:[buildFilter])
			let subscription = nostr.Subscribe(sub_id: "_PROF_NOTES_\(self.targetUser.description)", filters: [buildFilter])
			let tx = try self.dbux.eventsEngine.transact(readOnly:false)
			for curRelay in self.dbux.eventsEngine.relaysEngine.userRelayConnections {
				try self.dbux.eventsEngine.relaysEngine.addOrUpdate(subscriptions:[subscription], to:curRelay.key, tx: tx)
			}
			try tx.commit()

//			if showReplies == true {
//				newPosts = newPosts.filter { $0.event.isReply() == false }
//			}

//			self.logger.info("adding \(newPosts.count) new posts.")
//			let filteredPosts = newPosts.filter { !postUIDs.contains($0.event.uid) }
//
//			postUIDs.formUnion(filteredPosts.map { $0.event.uid })
//			// Use a temporary variable to store the updated posts
//			var updatedPosts = sortPosts(posts + filteredPosts)
//
//			// Trimming excess posts if needed
//			self.posts = updatedPosts
		}


		@MainActor func beganShowing(_ event: nostr.Event) {
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

		@MainActor private func trimPostsIfNeeded() {
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
		@MainActor private func updateContentIfNeeded() {
			guard let range = shownPostIndexRange else { return }
			// Determine if we should load more content based on the shown post index range
			let threshold = Int(batchSize) / 2

			if posts.count - range.upperBound <= threshold {
				// Load more content when the user is close to the bottom
				Task { [weak self] in
					try await self?.loadPosts()
				}
			}
		}


		@MainActor func stoppedShowing(_ event: nostr.Event) {
			showingEvents.remove(event)
			logger.info("no longer showing event id \(event.uid.description.prefix(5))", metadata: ["total_showing": "\(showingEvents.count)"])
		}

		@MainActor func startModel() {
			Task.detached { [weak self, hol = dbux.eventsEngine.relaysEngine.holder] in
				await self?.onScroll()

				// begin consuming the events as they come off the relay engine
				for await curEvents in hol {
					guard let self = self else { return }
					let lastEvent = await self.posts.last?.event.created
					guard Task.isCancelled == false else { return }


					var buildEvents = Set<nostr.Event>()
					var buildKeys = Set<nostr.Key>()
					for curEv in curEvents {
						print("PROF EVENT: \(curEv.0)")
						if curEv.1.kind == .text_note && curEv.1.pubkey == self.targetUser {
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
		@MainActor func stopModel() {
			posts.removeAll()
			postUIDs.removeAll()
			showingEvents.removeAll()
			shownPostIndexRange = nil
		}
	}
	
	@Environment(\.sizeCategory) var sizeCategory
	let dbux:DBUX
	let pubkey:nostr.Key
	let profile: nostr.Profile
	@ObservedObject var model:ProfileViewModel
	init(dbux:DBUX, pubkey:nostr.Key, profile:nostr.Profile) {
		self.dbux = dbux
		self.pubkey = pubkey
		self.profile = profile
		self.model = ProfileViewModel(dbux:dbux, showReplies:true, targetUser:self.pubkey)
	}
	@State var showSheet = false
	@State private var headerOffset: CGFloat = 0

	var body: some View {
		 GeometryReader { geometry in
			 ScrollView {
				 ScrollViewReader { scrollProxy in
					 VStack(alignment: .leading) {
						 
						 // big mega z stack
						 ZStack(alignment: .bottom) {
							 GeometryReader { innerGeometry in
								 BannerBackgroundWithGradientView(dbux: dbux, pubkey: pubkey, profile: profile)
								 // VStack with frame inside safe area
								 VStack(alignment: .trailing) {
									 if (dbux.keypair.pubkey == pubkey) {
										 HStack {
											 NavigationLink(destination: UI.UserExperienceSettingsScreen(dbux:dbux)) { // Replace with the destination view for your settings
												 Image(systemName: "gear")
													 .font(.system(size: 18)) // Adjust the font size to make the button smaller
													 .foregroundColor(.white)
													 .padding(10) // Adjust padding to match the size of the RoundedRectangle
													 .background(RoundedRectangle(cornerRadius: 25) // RoundedRectangle with a corner radius matching half of the frame height
														.fill(Color.black.opacity(0.25))) // Fill the RoundedRectangle with a semi-transparent primary color
													 .frame(width: 50, height: 50) // Set the frame size of the RoundedRectangle
												 
											 }
											 Spacer()
											 NavigationLink(destination: UI.Profile.ProfileMetadataEditView(dbux:dbux, profile: profile, pubkey: pubkey.description)) {
												 Text("Edit")
													 .font(.system(size: 14))
													 .foregroundColor(.white)
													 .padding(.horizontal, 12)
													 .padding(.vertical, 6)
													 .background(Color.blue)
													 .cornerRadius(4)
											 }
										 }
										 .padding(.top, innerGeometry.safeAreaInsets.top)
										 .padding(.horizontal, 13)
										 .frame(width: geometry.size.width, alignment: .trailing)
									 } else {
										 HStack() {
											 Spacer()
											 Text("Follow")
												 .font(.system(size: 14))
												 .foregroundColor(.white)
												 .padding(.horizontal, 12)
												 .padding(.vertical, 6)
												 .background(Color.blue)
												 .cornerRadius(4)
										 }
									 }
									 Spacer()
									 HStack(alignment: .center) {
										 ProfilePictureView(dbux:dbux, pictureURL: URL(string: profile.picture ?? ""))
											 .padding(.trailing, 8)
										 
										 DisplayNameView(dbux:dbux, displayName: profile.display_name, userName: profile.name, isVerified: profile.nip05 != nil)
										 
										 HStack {
											 Spacer()
											 
											 UI.Profile.Actions.BadgeButton(dbux:dbux, pubkey: pubkey, profile:profile, sheetActions:[.dmButton, .sendTextNoteButton, .shareButton], showModal: $showSheet)
											 
										 }.contentShape(Rectangle()).frame(height:50)
											 .background(Color.clear)
											 .gesture(
												TapGesture()
													.onEnded { _ in
														showSheet.toggle()
													}
											 )
									 }
									 .padding(.horizontal, 16)
								 }
								 .padding(.top, geometry.safeAreaInsets.top)
							 }.background(GeometryReader { proxy in
								 Color.clear.preference(key: HeaderOffsetKey.self, value: proxy.frame(in: .named("scroll")).minY)
							 })
						 }
						 .offset(y: max(-headerOffset, 0))
						 .edgesIgnoringSafeArea(.top)
						 .frame(width: geometry.size.width, height: 220)
						 
						 ProfileInfoView(profile:profile)
						 Spacer()
					 }
					 // Apply the onPreferenceChange modifier
								.onPreferenceChange(HeaderOffsetKey.self) { offset in
									headerOffset = offset
								}
								.coordinateSpace(name: "scroll")
					 
					 ForEach(model.posts) { post in
						 Text("There is a post")
					 }
				 }
			 }
			 .offset(y: max(-headerOffset, 0))
			 .edgesIgnoringSafeArea(.top)
		 }.onAppear {
			 model.startModel()
			   }.onDisappear {
				   model.stopModel()
			   }
	 }
 }
