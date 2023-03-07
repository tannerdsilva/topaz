//
//  AccountPickerView.swift
//  topaz
//
//  Created by Tanner Silva on 3/5/23.
//

import SwiftUI

struct AccountPickerView: View {
	@ObservedObject var users:ApplicationModel.UserStore
	
    var body: some View {
		  Text(verbatim:"")
    }
}

struct AccountPickerView_Previews: PreviewProvider {
  static var previews: some View {
    AccountPickerView(users:Topaz().localData.userStore)
  }
}
