//
//  PublicKeyView.swift
//  topaz
//
//  Created by Tanner Silva on 4/18/23.
//

import Foundation
import SwiftUI

extension UI.Profile {
	struct PublicKeyView:View {
		let key:nostr.Key
		
		@Environment(\.sizeCategory) var sizeCategory
		
		var body:some View {
			HStack {
				Image(systemName: "key.fill")
					.resizable()
					.renderingMode(.template)
					.aspectRatio(contentMode: .fit)
					.frame(width: 20, height: 20)
					.foregroundColor(.accentColor)
				UI.CryptoSignatureText(text:key.getNpubString()).frame(idealHeight: UI.CryptoSignatureText.lineHeight(for: sizeCategory))
			}
		}
	}
}
