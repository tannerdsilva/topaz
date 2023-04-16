//
//  AccountPickerView.swift
//  topaz
//
//  Created by Tanner Silva on 3/5/23.
//

import SwiftUI

struct AccountPickerView: View {
	let dbux:DBUX
	
    var body: some View {
		VStack {
			// Title Bar
			CustomTitleBar(dbux:dbux)
			
			Spacer()
			
			Text("this is the account picker")

			Spacer()

		}.background(.gray).frame(maxWidth:.infinity)
    }
}

//struct AccountPickerView_Previews: PreviewProvider {
//  static var previews: some View {
//	  AccountPickerView(ue:try! UE(keypair: Topaz.tester_account))
//  }
//}
