//
//  UserFacingTextContentView.swift
//  topaz
//
//  Created by Tanner Silva on 4/18/23.
//

import Foundation
import SwiftUI

extension View {
	   func readHeight(_ height: Binding<CGFloat>) -> some View {
		   self.modifier(UI.Events.BackgroundGeometryReader(height: height))
	   }
   }

extension UI.Events {
	struct MeasuredText: View {
		let text: AttributedString
		let fontSize: CGFloat

		var body: some View {
			Text(text)
				.font(.system(size: fontSize))
				.lineLimit(nil)
		}
	}
	struct BackgroundGeometryReader: ViewModifier {
		@Binding var height: CGFloat

		func body(content: Content) -> some View {
			content
				.background(GeometryReader { geometry in
					Color.clear
						.preference(key: ViewHeightPreferenceKey.self, value: geometry.size.height)
				})
				.onPreferenceChange(ViewHeightPreferenceKey.self) { newValue in
					height = newValue
				}
		}
	}

	struct ViewHeightPreferenceKey: PreferenceKey {
		static var defaultValue: CGFloat = 0

		static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
			value = nextValue()
		}
	}

	struct UserFacingTextContentView: View {
		let content: String
		enum Segment: Hashable {
			case text(String)
			case url(String)
			case hashtag(String)
		}
		
		static func fontSize(for sizeCategory: ContentSizeCategory, availableWidth: CGFloat) -> CGFloat {
			let baseFontSize: CGFloat
			
			switch sizeCategory {
			case .accessibilityExtraExtraExtraLarge:
				baseFontSize = 45
			case .accessibilityExtraExtraLarge, .accessibilityExtraLarge, .accessibilityLarge, .accessibilityMedium:
				baseFontSize = 32
			default:
				baseFontSize = 22
			}
			
			let widthFactor = availableWidth / 375.0 // Assuming 375 points as the reference width
			return baseFontSize * widthFactor
		}

		private func renderRichText() -> Result<AttributedString, Swift.Error> {
			do {
				var attributedString = AttributedString(content)
				let urlRegex = try Regex("((https|http)://)((\\w|-)+)(([.]|[/])((\\w|-)+))+")
				let hashtagPattern = try Regex("#[\\p{L}0-9_]*")
				
				for curHTTPMatch in content.matches(of:urlRegex) {
					let asAttributedRange = Range<AttributedString.Index>(curHTTPMatch.range, in: attributedString)!
					attributedString[asAttributedRange].foregroundColor = .blue
					attributedString[asAttributedRange].underlineStyle = .thick
				}
				for curHashTagMatch in content.matches(of:hashtagPattern) {
					let asAttributedRange = Range<AttributedString.Index>(curHashTagMatch.range, in: attributedString)!
					attributedString[asAttributedRange].foregroundColor = .purple
				}
				return .success(attributedString)
			} catch let error {
				return .failure(error)
			}
		}
		
		var body: some View {
			Group {
				switch renderRichText() {
				case .success(let richText):
					Text(richText)
						.font(.body)
						.foregroundColor(.primary)
						.multilineTextAlignment(.leading)
				case .failure:
					Text(content) // Fallback to plain text if rich text rendering fails
				}
			}
		}
	}
}



extension NSRegularExpression {
	func matches(in string: String) -> [NSTextCheckingResult] {
		let nsRange = NSRange(string.startIndex..<string.endIndex, in: string)
		return matches(in: string, options: [], range: nsRange)
	}
}
