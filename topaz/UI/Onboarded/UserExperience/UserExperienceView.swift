////
////  UserExperienceView.swift
////  topaz
////
////  Created by Tanner Silva on 3/6/23.
////
//
import SwiftUI

struct UserExperienceView: View {
	@Environment(\.scenePhase) private var scenePhase
	
	let dbux:DBUX
	@ObservedObject var context:DBUX.ContextEngine
	@ObservedObject var profileEngine:DBUX.ProfilesEngine
	
	@State var showingAccountPicker:Bool = false
	init(dbux:DBUX) {
		self.dbux = dbux
		self.context = dbux.contextEngine
		self.profileEngine = dbux.eventsEngine.profilesEngine
	}
    var body: some View {
		GeometryReader { geometry in
			VStack {
				switch context.viewMode {
				case .home:
					NavigationStack {
						HomeView(dbux: dbux).frame(width: geometry.size.width)
					}
				case .notifications:
					MentionsView().frame(width: geometry.size.width)
				case .dms:
					MessagesView(isUnread: $context.badgeStatus.dmsBadge).frame(width: geometry.size.width)
				case .search:
					SearchView().frame(width: geometry.size.width)
				case .profile:
					NavigationStack {
						ProfileDetailView(dbux:dbux, pubkey: dbux.keypair.pubkey, profile:profileEngine.currentUserProfile, showBack: false, profileEngine: dbux.eventsEngine.profilesEngine).frame(width: geometry.size.width)
					}
				}
				Spacer()
				UI.NavBar(dbux: dbux, appData:dbux.application, viewMode: $context.viewMode, badgeStatus: $context.badgeStatus, showAccountPicker: $showingAccountPicker)
					.frame(maxWidth:geometry.size.width, maxHeight: 70)
			}
		}.background(Color(.systemBackground)).onChange(of:scenePhase) { newValue in
			switch newValue {
			case .active:
				Task.detached { [disp = self.dbux.dispatcher] in
					await disp.fireEvent(DBUX.Notification.applicationBecameFrontmost)
				}
			case .inactive:
				Task.detached { [disp = self.dbux.dispatcher] in
					await disp.fireEvent(DBUX.Notification.applicationMovedToBackground)
				}
				break;
			case .background:
				
				break;
			@unknown default:
				break;
			}
		}
	}
}

struct HomeView: View {
	let dbux:DBUX
	var body: some View {
		VStack {
			CustomTitleBar(dbux:dbux)
			Spacer()
			UI.TimelineView(dbux:dbux, postsOnlyModel:UI.TimelineViewModel(dbux:dbux, showReplies: false), withRepliesModel:UI.TimelineViewModel(dbux:dbux, showReplies: true))
		}
	}
}

struct MentionsView: View {
	var body: some View {
		UnderConstructionView(unavailableViewName:"Notifications View")
	}
}

struct MessagesView: View {
	@Binding var isUnread:Bool
	
	var body: some View {
		UnderConstructionView(unavailableViewName:"Direct Messages")
		
	}
}

struct SearchView: View {
	var body: some View {
		UnderConstructionView(unavailableViewName:"Search and Explore")
	}
}

//struct PV: View {
//	let dbux:DBUX
//
//	var body: some View {
//		ProfileDetailView(dbux:dbux, pubkey:dbux.keypair.pubkey, profileEngine:dbux.eventsEngine.profilesEngine)
//	}
//}

struct DisplayNameText: View {
	let text: String

	var body: some View {
		Text(text)
			.font(.system(size: 18, weight: .bold, design: .rounded))
			.foregroundColor(.primary)
	}
}

struct ActionBarView: View {
	@State private var isLiked = false
	@State private var walletAction = false

	var body: some View {
		HStack {
			Button(action: {
				print("Reply tapped")
			}) {
				Image(systemName: "arrowshape.turn.up.left")
			}
			.foregroundColor(.blue)
			Spacer()
			Button(action: {
				print("Repost tapped")
			}) {
				Image(systemName: "arrow.2.squarepath")
			}
			.foregroundColor(.blue)
			Spacer()
			Button(action: {
				isLiked.toggle()
				print("Like tapped")
			}) {
				Image(systemName: isLiked ? "heart.fill" : "heart")
			}
			.foregroundColor(.blue)
			Spacer()
			Button(action: {
				walletAction.toggle()
				print("Wallet tapped")
			}) {
				Image(systemName: "dollarsign.circle")
			}
			.foregroundColor(.blue)
			Spacer()
			Button(action: {
				print("Share tapped")
			}) {
				Image(systemName: "square.and.arrow.up")
			}
			.foregroundColor(.blue)
		}
		.font(.system(size: 20))
				.padding(.horizontal, 8)
				.padding(.vertical, 4)
//				.background(BubbleShape().fill(Color.gray.opacity(0.15)))
				.shadow(radius: 8)
	}
}


struct EventViewCell: View {
	let dbux:DBUX
	let event: nostr.Event
	let profile: nostr.Profile?
	let showActions:Bool
	@Binding var selectedEvent:nostr.Event?
	
	@Environment(\.colorScheme) var colorScheme
	
	var dateFormatter: DateFormatter {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .short
		return formatter
	}

	@ViewBuilder var profileHStack:some View {
		HStack {
			if let profilePicture = profile?.picture, let url = URL(string: profilePicture) {
				NavigationLink(destination:ProfileDetailView(dbux: dbux, pubkey:event.pubkey, profile: profile!, showBack:true, profileEngine:dbux.eventsEngine.profilesEngine)) {
					UI.Images.AssetPipeline.AsyncImage(url: url, actor:dbux.storedImageActor) { image in
						image
							.resizable()
							.aspectRatio(contentMode: .fill)
					} placeholder: {
						ProgressView()
					}
					.frame(width: 50, height: 50)
					.cornerRadius(25)
				}
				
			} else {
				Image(systemName: "person.crop.circle.fill")
					.resizable()
					.frame(width: 50, height: 50)
					.foregroundColor(.gray)
			}
			
			VStack(alignment: .leading, spacing: 2) {
				UpperProfileView.DisplayNameView(dbux:dbux, displayName:profile?.display_name, userName:profile?.name, isVerified:profile?.nip05 != nil)
			}
			Spacer()
			RelativeDateDisplay(date: event.created)
		}
	}
	var withHiddenActionButton: some View {
	   VStack(alignment: .leading, spacing: 8) {
		   profileHStack

		   UI.Events.UserFacingTextContentView(dbux:dbux, event: event)

		   if self.selectedEvent == event {
			   HStack {
				   ActionBarView()
			   }
		   }
	   }
	   .padding()
	   .background(selectedEvent == event ? highlightColor : Color.clear)
		.onTapGesture {
		   withAnimation {
			   self.selectedEvent = self.selectedEvent == event ? nil : event
		   }
	   }
   }
	
	var withAlwaysShownActionButtons: some View {
		VStack(alignment: .leading, spacing: 8) {
			profileHStack

			UI.Events.UserFacingTextContentView(dbux:dbux, event: event)

			HStack {
				ActionBarView()
			}
		}
		.padding()
	}
	
	var body:some View {
		if self.showActions {
			withAlwaysShownActionButtons
		} else {
			withHiddenActionButton
		}
	}
	
	var highlightColor: Color {
			switch colorScheme {
			case .dark:
				return Color.white.opacity(0.15)
			case .light:
				return Color.black.opacity(0.15)
			@unknown default:
				return Color.black.opacity(0.15)
			}
		}
}

struct CustomTitleBar: View {
	let dbux:DBUX
	@ObservedObject var contextEngine:DBUX.ContextEngine
	@State var showingCompose = false
	
	init(dbux:DBUX) {
		self.dbux = dbux
		contextEngine = dbux.contextEngine
	}
	var body: some View {
		HStack {
			UI.Relays.ConnectionStatusWidget(dbux:dbux, relays: dbux.eventsEngine.relaysEngine)
			Spacer().frame(width:5)
			UI.Relays.SyncStatusWidget(dbux:dbux, relays:dbux.eventsEngine.relaysEngine)
			UI.CustomToggle(isOn:$contextEngine.timelineRepliesToggleEnabled, symbolOn:"arrowshape.turn.up.backward.fill", symbolOff:"person.fill").frame(width:60)
			Spacer()
			Button("Compose", action: {
				showingCompose = true
			})
			Spacer().frame(width:10)
		}
		.padding(.vertical, 8) // Adjust the vertical padding for less height
		.frame(height: 44) // Set the height of the title bar
		.background(Color(.systemBackground))
		.sheet(isPresented:$showingCompose) {
			UI.Events.NewPostView(dbux:dbux, profile: dbux.eventsEngine.profilesEngine.currentUserProfile, publicKey:dbux.keypair.pubkey, isShowingSheet: $showingCompose)
		}
	}
}
