//
//  AccountPickerView.swift
//  topaz
//
//  Created by Tanner Silva on 3/5/23.
//

import SwiftUI

struct AccountPickerView: View {
	@ObservedObject var ue:UE
	
    var body: some View {
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

			// Navigation Bar
			HStack {
				CustomTabBar(viewMode:$ue.viewMode, badgeStatus:$ue.badgeStatus)
			}
		}.background(.gray).frame(maxWidth:.infinity)
    }
}

struct AccountPickerView_Previews: PreviewProvider {
  static var previews: some View {
	  AccountPickerView(ue:try! UE(keypair: Topaz.tester_account))
  }
}
