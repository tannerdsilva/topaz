//
//  RelayProtocolView.swift
//  topaz
//
//  Created by Tanner Silva on 4/16/23.
//

import Foundation
import SwiftUI

extension UI.Relays {
	struct RelayProtocolView: View {
		enum ProtocolType {
			case wss
			case ws
			case unknown
		}
		
		let protocolType: ProtocolType
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
		
		init(url: URL?) {
			if url == nil {
				self.protocolType = .unknown
			} else {
				if url!.scheme == "ws" {
					self.protocolType = .ws
				} else if url!.scheme == "wss" {
					self.protocolType = .wss
				} else {
					self.protocolType = .unknown
				}
			}
		}
		
		var body: some View {
			Text(protocolTypeText)
				.font(.system(size: fontSize, design: .monospaced)) // Use a monospaced font
				.padding(.horizontal, paddingSize)
				.padding(.vertical, paddingSize / 2)
				.background(RoundedRectangle(cornerRadius: 4).fill(fillColor))
				.overlay(RoundedRectangle(cornerRadius: 4).stroke(outlineColor, lineWidth: outlineWidth))
				.foregroundColor(.white)
		}
		
		private var protocolTypeText: String {
			switch protocolType {
			case .ws:
				return "ws"
			case .wss:
				return "wss"
			case .unknown:
				return "?"
			}
		}
	}
}
