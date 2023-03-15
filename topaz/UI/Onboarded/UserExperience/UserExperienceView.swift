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
	
    var body: some View {
		NavigationStack {
			VStack {
				// Title Bar
				CustomTitleBar()
				
				Spacer()
				
				switch ue.viewMode {
				case .home:
					HomeView(ue:ue)
				case .notifications:
					MentionsView()
				case .dms:
					MessagesView(isUnread:$ue.badgeStatus.dmsBadge)
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
			CustomTabBar(viewMode:$ue.viewMode, badgeStatus:$ue.badgeStatus)
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

struct CustomTabBar: View {
	@Binding var viewMode:UE.ViewMode
	@Binding var badgeStatus:UE.ViewBadgeStatus

	var body: some View {
		HStack {
			TabButton(myView:.home, icon: "house.fill", index: 0, selectedTab:$viewMode, accentColor: .cyan, showBadge: $badgeStatus.homeBadge).frame(maxWidth:.infinity)
			TabButton(myView:.notifications, icon: "bell.fill", index: 1, selectedTab:$viewMode, accentColor: .orange, showBadge: $badgeStatus.notificationsBadge).frame(maxWidth:.infinity)
			TabButton(myView:.dms, icon: "envelope.fill", index: 2, selectedTab:$viewMode, accentColor: .cyan, showBadge: $badgeStatus.dmsBadge).frame(maxWidth:.infinity)
			TabButton(myView:.search, icon: "magnifyingglass", index: 3, selectedTab:$viewMode, accentColor: .orange, showBadge: $badgeStatus.searchBadge).frame(maxWidth:.infinity)
			TabButton(myView:.profile, icon: "person.fill", index: 4, selectedTab:$viewMode, accentColor: .cyan, showBadge: $badgeStatus.profileBadge).frame(maxWidth:.infinity)
		}
		.padding(.init(top: 5, leading:0, bottom: 10, trailing:0))
		.background(Color(.systemBackground))
	}
}

struct TabButton: View {
	let myView:UE.ViewMode
	let icon: String
	let index: Int
	@Binding var selectedTab:UE.ViewMode
	let accentColor: Color
	@Binding var showBadge: Bool
	
	var body: some View {
		Button(action: {
			selectedTab = myView
			if showBadge == true {
				showBadge = false
			}
		}) {
			ZStack {
				Image(systemName: icon)
					.foregroundColor(selectedTab == myView ? accentColor : .gray)
					.frame(width: 44, height: 44)
				
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
	@State private var connectedServers = 6
	@State private var totalServers = 8
	
	var body: some View {
		GeometryReader { geometry in
			let circleSize: CGFloat = 6
			let spacing: CGFloat = 4
			let maxCircles = Int((geometry.size.width - spacing) / (circleSize + spacing))
			
			if totalServers <= maxCircles {
				VStack {
					HStack(spacing: spacing) {
						ForEach(0..<totalServers) { index in
							Circle()
								.fill(index < connectedServers ? Color.green : Color.red)
								.frame(width: circleSize, height: circleSize)
						}
					}
					Text("\(connectedServers)/\(totalServers)")
						.font(.system(size: 12))
						.foregroundColor(.white)
				}
				.frame(width: geometry.size.width, height: geometry.size.height)
			} else {
				VStack {
					ProgressRing(progress: Double(connectedServers) / Double(totalServers))
						.stroke(Color.green, lineWidth: 4)
						.frame(width: 22, height: 22)
					Text("\(connectedServers)/\(totalServers)")
						.font(.system(size: 12))
						.foregroundColor(.white)
				}
				.frame(width: geometry.size.width, height: geometry.size.height)
			}
		}
		.frame(width: 45, height: 30)
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

struct CustomTitleBar: View {
	var body: some View {
		HStack {
			Spacer()
			Text("Your App Name")
				.font(.system(size: 16, weight: .bold))
				.foregroundColor(Color(.systemBackground))
			Spacer()
			ConnectionStatusIndicator()
		}
		.padding(.vertical, 8) // Adjust the vertical padding for less height
		.frame(height: 44) // Set the height of the title bar
		.background(Color(.systemBackground))
	}
}

struct UserExperienceView_Previews: PreviewProvider {
	static var previews: some View {
		UserExperienceView(ue:try! UE(keypair:Topaz.tester_account))
	}
}
