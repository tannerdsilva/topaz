////
////  UserExperienceView.swift
////  topaz
////
////  Created by Tanner Silva on 3/6/23.
////
//
import SwiftUI

struct UserExperienceView: View {
	@ObservedObject var ue:UE
	@ObservedObject var context:UE.Context
	
	init(ue:UE) {
		self.ue = ue
		self.context = ue.contextDB
	}
    var body: some View {
		NavigationStack {
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
					PV()
				}
				
				Spacer()
				
			}.background(.gray).frame(maxWidth:.infinity)
		}
		// Navigation Bar
		HStack {
			CustomTabBar(viewMode:$context.viewMode, badgeStatus:$context.badgeStatus)
		}
    }
}


//
//import SwiftUI
//
//struct UserExperienceView: View {
//	@ObservedObject var ue:UE
//
//	var body: some View {
//		VStack {
//			Spacer()
//
//			NavigationView {
//				switch ue.viewMode {
//				case .home:
//					HomeView()
//				case .notifications:
//					MentionsView()
//				case .dms:
//					MessagesView()
//				case .search:
//					SearchView()
//				case .profile:
//					PV()
//				}
//			}
//
//			CustomTabBar(viewMode:$ue.viewMode)
//		}
//		.edgesIgnoringSafeArea(.bottom)
//	}
//}

struct TabButton: View {
	let myView:UE.ViewMode
	let icon: String
	let index: Int
	@Binding var selectedTab: UE.ViewMode
	let accentColor: Color
	@Binding var showBadge: Bool
	let profileImage: Image?

	var body: some View {
		Button(action: {
			selectedTab = myView
			showBadge = false
		}) {
			ZStack {
				// Use this conditional to display the profile image or the default icon
				if myView == .profile, let profileImg = profileImage {
					profileImg
						.resizable()
						.aspectRatio(contentMode: .fill)
						.clipShape(Circle())
						.frame(width: 44, height: 44)
				} else {
					Image(systemName: icon)
						.foregroundColor(selectedTab == myView ? accentColor : .gray)
						.frame(width: 44, height: 44)
				}
				
				if showBadge {
					ZStack {
						Circle()
							.fill(Color.red)
							.frame(width: 10, height: 10)
					}
					.offset(x: 10, y: -10)
				}
			}
		}
	}
}

struct CustomTabBar: View {
	@Binding var viewMode: UE.ViewMode
	@Binding var badgeStatus: UE.ViewBadgeStatus
	let profileImage: Image? = nil // Add this parameter for the profile image

	var body: some View {
		HStack {
			TabButton(myView: .home, icon: "house.fill", index: 0, selectedTab: $viewMode, accentColor: .orange, showBadge: $badgeStatus.homeBadge, profileImage: nil)
				.frame(maxWidth: .infinity)

			TabButton(myView: .notifications, icon: "bell.fill", index: 1, selectedTab: $viewMode, accentColor: .cyan, showBadge: $badgeStatus.notificationsBadge, profileImage: nil)
				.frame(maxWidth: .infinity)

			TabButton(myView: .dms, icon: "envelope.fill", index: 2, selectedTab: $viewMode, accentColor: .pink, showBadge: $badgeStatus.dmsBadge, profileImage: nil)
				.frame(maxWidth: .infinity)

			TabButton(myView: .search, icon: "magnifyingglass", index: 3, selectedTab: $viewMode, accentColor: .orange, showBadge: $badgeStatus.searchBadge, profileImage: nil)
				.frame(maxWidth: .infinity)

			TabButton(myView: .profile, icon: "person.fill", index: 4, selectedTab: $viewMode, accentColor: .cyan, showBadge: $badgeStatus.profileBadge, profileImage: profileImage) // Pass the profile image here
				.frame(maxWidth: .infinity)
		}
		.padding(.top)
		.frame(maxWidth: .infinity).background(Color(.systemBackground))
	}
}



struct HomeView: View {
	let ue:UE
	var body: some View {
		NavigationLink("Push view", destination: {
			AccountPickerView(ue:ue)
		})
	}
}

struct MentionsView: View {
	var body: some View {
		Text("Mentions")
	}
}

struct MessagesView: View {
	@Binding var isUnread:Bool
	
	var body: some View {
		VStack {
			Text("Messages")
			
			if (isUnread == false) {
				Button(action: {
					isUnread = true
				}, label: { Text("Mark as unread") })
			}
		}
		
	}
}

struct SearchView: View {
	var body: some View {
		Text("Search")
	}
}

struct PV: View {
	var body: some View {
		Text("Profile")
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
				if succ.count <= ConnectionDotView.maxCirclesInFrame(maxWidth:geometry.size.width, maxHeight:geometry.size.height, circleSize:circleSize, spacing:spacing) {
					ConnectionDotView(spacing:spacing, circleSize:circleSize, status:succ).sheet(isPresented: $showModal) {
					  ModalView()
				  }
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
			.frame(width: geometry.size.width, height: geometry.size.height)
		}
		.frame(width: 45, height: 30)
		.onTapGesture {
//			withAnimation(.easeInOut(duration: 0.3)) {
//				isTextVisible.toggle()
//			}
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
	let circleSize: CGFloat
	let status: [RelayConnection.State]
	
	var body: some View {
		GeometryReader { geometry in
			let numberOfColumns = Int((geometry.size.width - spacing) / (circleSize + spacing))
			let numberOfRows = Int((geometry.size.height - spacing) / (circleSize + spacing))
			let columns = Array(repeating: GridItem(.fixed(circleSize), spacing: spacing), count: numberOfColumns)
			
			let horizontalPadding = (geometry.size.width - CGFloat(min(numberOfColumns, status.count)) * (circleSize + spacing) + spacing) / 2
			let usedRows = max(1, Int(ceil(Double(status.count) / Double(numberOfColumns))))
			let verticalPadding = (geometry.size.height - CGFloat(usedRows) * (circleSize + spacing) + spacing) / 2
			
			LazyVGrid(columns: columns, spacing: spacing) {
				ForEach(status.indices, id: \.self) { index in
					Circle()
						.fill(Self.colorForConnectionState(status[index]))
						.frame(width: circleSize, height: circleSize)
				}
			}
			.padding(.horizontal, horizontalPadding)
			.padding(.vertical, verticalPadding)
		}
	}
	
	fileprivate static func colorForConnectionState(_ state: RelayConnection.State) -> Color {
		switch state {
		case .disconnected:
			return Color.red
		case .connecting:
			return Color.yellow
		case .connected:
			return Color.green
		}
	}
	
	static func maxCirclesInFrame(maxWidth: CGFloat, maxHeight: CGFloat, circleSize: CGFloat, spacing: CGFloat) -> Int {
		let numberOfColumns = Int((maxWidth - spacing) / (circleSize + spacing))
		let numberOfRows = Int((maxHeight - spacing) / (circleSize + spacing))
		return numberOfColumns * numberOfRows
	}
}

struct ModalView: View {
	@Environment(\.dismiss) var dismiss

	var body: some View {
		VStack {
			Text("This is a full screen modal view")
			Button("Dismiss") {
				dismiss()
			}
		}
	}
}



struct CustomTitleBar: View {
	let ue:UE
	var body: some View {
		HStack {
			Spacer()
			Text("Your App Name")
				.font(.system(size: 16, weight: .bold))
				.foregroundColor(Color(.lightText))
			Spacer()
			ConnectionStatusIndicator(relays: ue.relaysDB)
		}
		.padding(.vertical, 8) // Adjust the vertical padding for less height
		.frame(height: 44) // Set the height of the title bar
		.background(Color(.systemBackground))
	}
}
