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
	
	init(dbux:DBUX) {
		self.dbux = dbux
		self.context = dbux.contextEngine
	}
    var body: some View {
		VStack {
			switch context.viewMode {
			case .home:
				HomeView(dbux:dbux)
			case .notifications:
				MentionsView()
			case .dms:
				MessagesView(isUnread:$context.badgeStatus.dmsBadge)
			case .search:
				SearchView()
			case .profile:
				ProfileDetailView(pubkey:dbux.keypair.pubkey.description, profile:dbux.profilesEngine.currentUserProfile)
			}
			Spacer()
			UI.NavBar(dbux:dbux, viewMode:$context.viewMode, badgeStatus:$context.badgeStatus)
				.frame(maxWidth: .infinity, maxHeight: 70)
		}.background(Color(.systemBackground)).border(.cyan).onChange(of:scenePhase) { newValue in
			switch newValue {
			case .active:
				Task.detached { [dbux = dbux] in
					let getItAll = await dbux.relaysEngine.getConnectionsAndStates()
					let getDisconnected = getItAll.1.values.filter({ $0 == .disconnected })
					if getDisconnected.count > 0 {
						Task.detached { [relays = getItAll.0] in
							await withTaskGroup(of:Void.self) { tg in
								for curRelay in relays {
									tg.addTask { [cr = curRelay] in
										try? await cr.value.connect()
									}
								}
							}
						}
					}
				}
			case .inactive:
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
		NavigationStack {
			CustomTitleBar(dbux:dbux)
			Spacer()
			TimelineView(dbux:dbux)
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

struct PV: View {
	let ue:DBUX
	
	var body: some View {
		ProfileDetailView(pubkey:ue.keypair.pubkey.description, profile:ue.profilesEngine.currentUserProfile)
	}
}

struct DisplayNameText: View {
	let text: String

	var body: some View {
		Text(text)
			.font(.system(size: 18, weight: .bold, design: .rounded))
			.foregroundColor(.primary)
	}
}


struct EventViewCell: View {
	let event: nostr.Event
	let profile: nostr.Profile?

	var dateFormatter: DateFormatter {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .short
		return formatter
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				if let profilePicture = profile?.picture, let url = URL(string: profilePicture) {
					AsyncImage(url: url) { image in
						image
							.resizable()
							.aspectRatio(contentMode: .fill)
					} placeholder: {
						ProgressView()
					}
					.frame(width: 50, height: 50)
					.cornerRadius(25)
				} else {
					Image(systemName: "person.crop.circle.fill")
						.resizable()
						.frame(width: 50, height: 50)
						.foregroundColor(.gray)
				}

				VStack(alignment: .leading, spacing: 2) {
					HStack(spacing: 4) {
						DisplayNameText(text: profile?.display_name ?? profile?.name ?? "Unknown")
						
						if profile?.nip05 != nil {
							Image(systemName: "checkmark.circle.fill")
								.foregroundColor(.blue)
								.font(.system(size: 18))
						}
					}
					
					Text("@\(profile?.name ?? "unknown")")
						.font(.subheadline)
						.foregroundColor(.gray)
				}
			}

			TextNoteContentView(content: event.content)

			
			HStack {
				Text(dateFormatter.string(from: event.created.exportDate()))
					.font(.caption)
					.foregroundColor(.gray)

				Spacer()

				// Validation status indicator
				switch event.validate() {
				case .success(let validationResult):
					if validationResult == .ok {
						Image(systemName: "checkmark.circle.fill")
							.foregroundColor(.green)
							.font(.system(size: 18))
					} else {
						Image(systemName: "exclamationmark.circle.fill")
							.foregroundColor(.red)
							.font(.system(size: 18))
					}
				case .failure(_):
					Image(systemName: "questionmark.circle.fill")
						.foregroundColor(.yellow)
						.font(.system(size: 18))
				}
				
				Spacer()
				if let boostedBy = event.boosted_by {
					HStack {
						Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
						Text(boostedBy)
					}
					.font(.caption)
					.foregroundColor(.accentColor)
				}

				Spacer()
				Text("Tags: \(event.tags.count)").font(.caption).foregroundColor(.gray)
			}
		}
		.padding()
		.background(Color(.systemBackground))
	}
}

struct CustomTitleBar: View {
	let dbux:DBUX
	var body: some View {
		HStack {
			Spacer()
			UI.Relays.ConnectionStatusWidget(relays: dbux.relaysEngine).border(.orange)
		}
		.padding(.vertical, 8) // Adjust the vertical padding for less height
		.frame(height: 44) // Set the height of the title bar
		.background(Color(.systemBackground))
	}
}
