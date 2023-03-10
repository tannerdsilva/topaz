//
//  UEDevView.swift
//  topaz
//
//  Created by Tanner Silva on 3/6/23.
//

import SwiftUI

struct UEDevView: View {
	@ObservedObject var ue:UE
	
    var body: some View {
		VStack {
			Text("DEV VIEW").dynamicTypeSize(.xxxLarge)
			Text(ue.keypair.pubkey)
		}
		
    }
}

struct UEDevView_Previews: PreviewProvider {
    static var previews: some View {
		UEDevView(ue:try! UE(keypair:Topaz.tester_account))
    }
}
