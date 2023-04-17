//
//  RelayProtocolView.swift
//  topaz
//
//  Created by Tanner Silva on 4/16/23.
//

import Foundation
import SwiftUI

struct RelayProtocolView: View {
	let protocolType: String
	let fillColor: Color = Color.gray.opacity(0.2)
	let outlineColor: Color = Color.gray.opacity(0.7)
	let outlineWidth: CGFloat = 1
	
	@Environment(\.sizeCategory) var sizeCategory
	
	var fontSize: CGFloat {
		switch sizeCategory {
		case .accessibilityExtraExtraExtraLarge:
			return 18
		case .accessibilityExtraExtraLarge, .accessibilityExtraLarge, .accessibilityLarge, .accessibilityMedium:
			return 14
		default:
			return 10
		}
	}
	
	var paddingSize: CGFloat {
		switch sizeCategory {
		case .accessibilityExtraExtraExtraLarge:
			return 12
		case .accessibilityExtraExtraLarge, .accessibilityExtraLarge, .accessibilityLarge, .accessibilityMedium:
			return 8
		default:
			return 6
		}
	}

	init(url: String) {
		if url.starts(with: "ws://") {
			self.protocolType = "ws://"
		} else if url.starts(with: "wss://") {
			self.protocolType = "wss://"
		} else {
			self.protocolType = ""
		}
	}

	var body: some View {
		Text(protocolType == "ws://" ? "ws" : "wss")
			.font(.system(size: fontSize))
			.padding(.horizontal, paddingSize)
			.padding(.vertical, paddingSize / 2)
			.background(RoundedRectangle(cornerRadius: 4).fill(fillColor))
			.overlay(RoundedRectangle(cornerRadius: 4).stroke(outlineColor, lineWidth: outlineWidth))
			.foregroundColor(.white)
	}
}
