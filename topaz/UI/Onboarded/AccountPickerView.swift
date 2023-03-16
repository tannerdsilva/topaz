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
			CustomTitleBar(ue:ue)
			
			Spacer()
			
			Text("this is the account picker")

			Spacer()

		}.background(.gray).frame(maxWidth:.infinity)
    }
}

struct AccountPickerView_Previews: PreviewProvider {
  static var previews: some View {
	  AccountPickerView(ue:try! UE(keypair: Topaz.tester_account))
  }
}
