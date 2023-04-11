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
	
	@ObservedObject var ue:UE
	@ObservedObject var context:UE.Context
	
	init(ue:UE) {
		self.ue = ue
		self.context = ue.contextDB
	}
    var body: some View {
		VStack {
//			NavigationStack {
				VStack {
					// Title Bar
					CustomTitleBar(ue:ue)
					
					Spacer()
					
					switch context.viewMode {
					case .home:
						HomeView(ue:ue)
					case .notifications:
						MentionsView()
					case .dms:
						MessagesView(isUnread:$ue.contextDB.badgeStatus.dmsBadge)
					case .search:
						SearchView()
					case .profile:
						ProfileDetailView(profile:ue.profilesDB.currentUserProfile!)
					}
					
					Spacer()
					
				}.frame(maxWidth:.infinity)
//			}
			// Navigation Bar
			HStack {
				CustomTabBar(ue:ue, viewMode:$context.viewMode, badgeStatus:$context.badgeStatus)
			}
		}.background(Color(.systemBackground)).onChange(of:scenePhase) { newValue in
				switch newValue {
				case .active:
					let getDisconnected = ue.relaysDB.userRelayConnectionStates.values.filter({ $0 == .disconnected })
					if getDisconnected.count > 0 {
						Task.detached { [relays = ue.relaysDB.userRelayConnections] in
							await withTaskGroup(of:Void.self) { tg in
								for curRelay in relays {
									tg.addTask { [cr = curRelay] in
										try? await cr.value.connect()
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

struct TabButton: View {
	let myView: UE.ViewMode
	let icon: String
	let index: Int
	@Binding var selectedTab: UE.ViewMode
	let accentColor: Color
	@Binding var showBadge: Bool
	@State var profileIndicate: nostr.Profile?
	@Environment(\.sizeCategory) var sizeCategory

	var imageSize: CGFloat {
		switch sizeCategory {
		case .accessibilityExtraExtraExtraLarge:
			return 45
		case .accessibilityExtraExtraLarge, .accessibilityExtraLarge, .accessibilityLarge, .accessibilityMedium:
			return 32
		default:
			return 22
		}
	}
	
	var badgeSize: CGFloat {
		return imageSize * 0.420
	}
	
	var body: some View {
			Button(action: {
				selectedTab = myView
				showBadge = false
			}) {
				ZStack {
					if let profileImgUrl = profileIndicate?.picture {
						AsyncImage(url: URL(string:profileImgUrl), content: { image in
							image
								.resizable()
								.aspectRatio(contentMode: .fill)
								.frame(width: imageSize, height: imageSize)
								.clipShape(Circle())
						}, placeholder: {
							ProgressView()
								.frame(width: imageSize, height: imageSize)
						})
					} else {
						Image(systemName: icon)
							.resizable()
							.scaledToFit()
							.foregroundColor(selectedTab == myView ? accentColor : .gray)
							.frame(width: imageSize, height: imageSize)
					}
					
					if showBadge {
						GeometryReader { geometry in
							ZStack {
								Circle()
									.fill(Color.red)
									.frame(width: badgeSize, height: badgeSize)
							}
							.position(x: geometry.size.width, y: geometry.size.height * 0.11)
						}
					}
				}
				.frame(width: imageSize, height: imageSize)
			}
		}
}

struct CustomTabBar: View {
	let ue:UE
	@Binding var viewMode: UE.ViewMode
	@Binding var badgeStatus: UE.ViewBadgeStatus
	@State private var showAccountPicker = false
	
	var body: some View {
		HStack {
			TabButton(myView: .home, icon: "house.fill", index: 0, selectedTab: $viewMode, accentColor: .orange, showBadge: $badgeStatus.homeBadge, profileIndicate: nil)
				.frame(maxWidth: .infinity)

			TabButton(myView: .notifications, icon: "bell.fill", index: 1, selectedTab: $viewMode, accentColor: .cyan, showBadge: $badgeStatus.notificationsBadge, profileIndicate: nil)
				.frame(maxWidth: .infinity)

			TabButton(myView: .dms, icon: "envelope.fill", index: 2, selectedTab: $viewMode, accentColor: .pink, showBadge: $badgeStatus.dmsBadge, profileIndicate: nil)
				.frame(maxWidth: .infinity)

			TabButton(myView: .search, icon: "magnifyingglass", index: 3, selectedTab: $viewMode, accentColor: .orange, showBadge: $badgeStatus.searchBadge, profileIndicate: nil)
				.frame(maxWidth: .infinity)

			TabButton(myView: .profile, icon: "person.fill", index: 4, selectedTab: $viewMode, accentColor: .cyan, showBadge: $badgeStatus.profileBadge, profileIndicate:ue.profilesDB.currentUserProfile) // Pass the profile image here
				.frame(maxWidth: .infinity)
				.onLongPressGesture {
				showAccountPicker.toggle()
			}
		}
		.padding(.top)
		.frame(maxWidth: .infinity).background(Color(.systemBackground))
	}
}



struct HomeView: View {
	let ue:UE
	var body: some View {
		TimelineView(ue:ue)
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
	let ue:UE
	
	var body: some View {
		ProfileDetailView(profile:ue.profilesDB.currentUserProfile!)
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
				Text(dateFormatter.string(from: event.created))
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

struct ConnectionStatusIndicator: View {
	@ObservedObject var relays: UE.RelaysDB
	@State private var isTextVisible = false
	@State var showModal = false

	var body: some View {
		GeometryReader { geometry in
			let circleSize: CGFloat = 6
			let spacing: CGFloat = 4
			let succ = relays.userRelayConnectionStates.sorted(by: { $0.key < $1.key }).compactMap({ $0.value })
			let connCount = succ.filter { $0 == .connected }

			VStack {
				if succ.count <= ConnectionDotView.maxShapesInFrame(maxWidth:geometry.size.width, maxHeight:geometry.size.height, shapeSize:circleSize, spacing:spacing) {
					ConnectionDotView(spacing:spacing, shapeSize:circleSize, status:succ)
				} else {
					ProgressRing(progress: Double(connCount.count) / Double(succ.count))
						.stroke(Color.green, lineWidth: 4)
						.frame(width: 22, height: 22)
				}

				if isTextVisible {
					Text("\(connCount.count)/\(succ.count)")
						.font(.system(size: 12))
						.foregroundColor(.white)
						.transition(.opacity)
				}
			}
			.frame(width: geometry.size.width, height: geometry.size.height).sheet(isPresented: $showModal) {
				ConnectionDetailsView(relayDB: relays)
			}
		}
		.frame(width: 45, height: 30)
		.onTapGesture {
			showModal.toggle()
			if isTextVisible {
				Task.detached {
					try await Task.sleep(nanoseconds:5_000_000_000)
					await MainActor.run { () -> Void in
						withAnimation(.easeInOut(duration:0.25)) {
							isTextVisible = true
						}
					}
				}
			}
		}
	}
}

struct ProgressRing: Shape {
	let progress: Double
	
	func path(in rect: CGRect) -> Path {
		var path = Path()
		path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
					radius: rect.width / 2,
					startAngle: .degrees(-90),
					endAngle: .degrees(-90 + 360 * progress),
					clockwise: false)
		return path
	}
}

struct ConnectionDotView: View {
	let spacing: CGFloat
	let shapeSize: CGFloat
	let status: [RelayConnection.State]

	var body: some View {
		GeometryReader { geometry in
			let numberOfColumns = Int((geometry.size.width - spacing) / (shapeSize + spacing))
			let numberOfRows = Int((geometry.size.height - spacing) / (shapeSize + spacing))
			let columns = Array(repeating: GridItem(.fixed(shapeSize), spacing: spacing), count: numberOfColumns)

			let horizontalPadding = (geometry.size.width - CGFloat(min(numberOfColumns, status.count)) * (shapeSize + spacing) + spacing) / 2
			let usedRows = max(1, Int(ceil(Double(status.count) / Double(numberOfColumns))))
			let verticalPadding = (geometry.size.height - CGFloat(usedRows) * (shapeSize + spacing) + spacing) / 2

			LazyVGrid(columns: columns, spacing: spacing) {
				ForEach(status.indices, id: \.self) { index in
					DotConnectionView(state: status[index])
						.frame(width: shapeSize, height: shapeSize)
				}
			}
			.padding(.horizontal, horizontalPadding)
			.padding(.vertical, verticalPadding)
		}
	}
	
	static func maxShapesInFrame(maxWidth: CGFloat, maxHeight: CGFloat, shapeSize: CGFloat, spacing: CGFloat) -> Int {
		let numberOfColumns = Int((maxWidth - spacing) / (shapeSize + spacing))
		let numberOfRows = Int((maxHeight - spacing) / (shapeSize + spacing))
		return numberOfColumns * numberOfRows
	}
}

struct DotConnectionView: View {
	let state: RelayConnection.State

	var body: some View {
		connectionShape(state: state)
			.foregroundColor(colorForConnectionState(state))
	}

	func connectionShape(state: RelayConnection.State) -> some Shape {
		switch state {
		case .disconnected:
			return AnyShape(Triangle())
		case .connecting:
			return AnyShape(Rectangle())
		case .connected:
			return AnyShape(Circle())
		}
	}

	func colorForConnectionState(_ state: RelayConnection.State) -> Color {
		switch state {
		case .disconnected:
			return Color.red
		case .connecting:
			return Color.yellow
		case .connected:
			return Color.green
		}
	}
}

struct Triangle: Shape {
	func path(in rect: CGRect) -> Path {
		var path = Path()

		path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
		path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
		path.closeSubpath()

		return path
	}
}

struct AnyShape: Shape {
	private let pathBuilder: (CGRect) -> Path

	init<S: Shape>(_ wrapped: S) {
		pathBuilder = { rect in
			return wrapped.path(in: rect)
		}
	}

	func path(in rect: CGRect) -> Path {
		return pathBuilder(rect)
	}
}

struct CustomTitleBar: View {
	let ue:UE
	var body: some View {
		HStack {
			Spacer()
			ConnectionStatusIndicator(relays: ue.relaysDB)
		}
		.padding(.vertical, 8) // Adjust the vertical padding for less height
		.frame(height: 44) // Set the height of the title bar
		.background(Color(.systemBackground))
	}
}
