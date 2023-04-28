//
//  WalletAddressView.swift
//  topaz
//
//  Created by Tanner Silva on 4/18/23.
//

import Foundation
import SwiftUI

extension UI.Profile {
	struct WalletAddressView:View {
		enum CryptoMode:UInt8 {
			case xmr
			case btc
			case ltc
			
			func assetName() -> String {
				switch self {
				case .xmr:
					return "xmr-logo"
				case .btc:
					return "btc-logo"
				case .ltc:
					return "ltc-logo"
				}
			}
			
			func getURIString(for wallet:String) -> String {
				switch self {
				case .xmr:
					return "monero://\(wallet)"
				case .btc:
					return "bitcoin://\(wallet)"
				case .ltc:
					return "litecoin://\(wallet)"
				}
			}
		}
		let wallet:String
		
		let config:CryptoMode
		@Environment(\.sizeCategory) var sizeCategory
		
		var body:some View {
			Link(destination:URL(string:config.getURIString(for: wallet))!) {
				HStack {
					Image(config.assetName())
						.resizable()
						.renderingMode(.template)
						.aspectRatio(contentMode: .fit)
						.frame(width: 20, height: 20)
						.foregroundColor(.orange)
					UI.CryptoSignatureText(text:wallet).frame(idealHeight: UI.CryptoSignatureText.lineHeight(for: sizeCategory))
				}
			}.buttonStyle(PlainButtonStyle())
		}
	}
}
