//
//  CryptoSignatureText.swift
//  topaz
//
//  Created by Tanner Silva on 4/20/23.
//

import Foundation
import SwiftUI

extension UI {
	struct CryptoSignatureText: View {
		@Environment(\.sizeCategory) var sizeCategory
		let text: String

		private static func fontSize(for sizeCategory: ContentSizeCategory) -> CGFloat {
			switch sizeCategory {
			case .accessibilityExtraExtraExtraLarge:
				return 24
			case .accessibilityExtraExtraLarge, .accessibilityExtraLarge, .accessibilityLarge, .accessibilityMedium:
				return 18
			default:
				return 14
			}
		}

		static func lineHeight(for sizeCategory: ContentSizeCategory) -> CGFloat {
			fontSize(for: sizeCategory) * 1.2
		}

		private func characterWidth() -> CGFloat {
			let font = UIFont.monospacedDigitSystemFont(ofSize: Self.fontSize(for: sizeCategory), weight: .regular)
			let attributes: [NSAttributedString.Key: Any] = [.font: font]
			let singleChar = NSAttributedString(string: "A", attributes: attributes)
			let size = singleChar.size()
			return size.width
		}

		private func displayKey(width: CGFloat) -> String {
			let characterWidth = characterWidth()
			let charactersToShow = max(Int(width / characterWidth) / 2, 1)
			let pkStr = text
			let prefix = pkStr.prefix(charactersToShow)
			let suffix = pkStr.suffix(charactersToShow)
			return "\(prefix):\(suffix)"
		}

		var body: some View {
			GeometryReader { geometry in
				Text(displayKey(width: geometry.size.width))
					.font(.system(size: Self.fontSize(for: sizeCategory), weight: .regular, design: .monospaced))
					.lineLimit(1)
					.minimumScaleFactor(0.5)
					.frame(width: geometry.size.width, height: Self.lineHeight(for: sizeCategory), alignment: .center)
					.position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.5)
			}
		}

	}
}
