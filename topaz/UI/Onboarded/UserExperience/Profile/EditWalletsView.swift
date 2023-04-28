//
//  EditWalletsView.swift
//  topaz
//
//  Created by Tanner Silva on 4/21/23.
//

import Foundation
import SwiftUI

extension UI.Profile {
//	struct WalletEditorView: View {
//		@State var wallets:nostr.Profile.Wallets
//		
//		@Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
//		
//		@State private var xmrAddress:String = ""
//		@State private var ltcAddress:String = ""
//		@State private var btcAddress:String = ""
//		
//		private let currencies = ["XMR": "Monero", "LTC": "Litecoin", "BTC": "Bitcoin"]
//		
//		init(wallets:nostr.Profile.Wallets) {
//			self.wallets = wallets
//		}
//		
//		func updateWalletAddress(symbol: String, address: String) {
//			if wallets == nil {
//				wallets = nostr.Profile.Wallets()
//			}
//			switch symbol {
//			case "XMR":
//				wallets?.xmr = address.isEmpty : address
//			case "LTC":
//				wallets?.ltc = address.isEmpty ? nil : address
//			case "BTC":
//				wallets?.btc = address.isEmpty ? nil : address
//			default:
//				break
//			}
//		}
//		
//		var body: some View {
//			Form {
//				Section(header: Text("Wallet Addresses")) {
//					TextField("Monero (XMR) Address", text: $xmrAddress)
//						.onChange(of: xmrAddress) { newValue in
//							updateWalletAddress(symbol: "XMR", address: newValue)
//						}
//					
//					TextField("Litecoin (LTC) Address", text: $ltcAddress)
//						.onChange(of: ltcAddress) { newValue in
//							updateWalletAddress(symbol: "LTC", address: newValue)
//						}
//					
//					TextField("Bitcoin (BTC) Address", text: $btcAddress)
//						.onChange(of: btcAddress) { newValue in
//							updateWalletAddress(symbol: "BTC", address: newValue)
//						}
//				}
//			}.onAppear {
//				xmrAddress = wallets?.xmr ?? ""
//				ltcAddress = wallets?.ltc ?? ""
//				btcAddress = wallets?.btc ?? ""
//			}
//		}
//	}
	
}
