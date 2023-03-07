//
//  UserExperienceView.swift
//  topaz
//
//  Created by Tanner Silva on 3/6/23.
//

import SwiftUI

struct UserExperienceView: View {
    @State var pubkey:String

    var body: some View {
        Text("You are within the user experience")
    }
}

struct UserExperienceView_Previews: PreviewProvider {
    static var previews: some View {
        UserExperienceView(pubkey: "foo")
    }
}
