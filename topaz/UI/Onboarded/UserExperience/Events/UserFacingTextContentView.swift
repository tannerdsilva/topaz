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
		let event: nostr.Event
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

		private func renderRichText() -> Result<(AttributedString, URL?), Swift.Error> {
			do {
				var content = event.content
				var attributedString = AttributedString(content)
				let urlRegex = try Regex("(https?://[\\w-]+(\\.[\\w-]+)+([\\w.,@?^=%&:/~+#-]*[\\w@?^=%&/~+#-])?)")
				let tagPlaceholderPattern = try Regex("#\\[(\\d+)\\]")
				let imageExtensions = ["jpg", "jpeg", "png", "gif"]

				var imageURL: URL?

				// First, process tag placeholders
				for (index, tag) in event.tags.enumerated() {
					let placeholder = "#[\(index)]"
					while let range = content.range(of: placeholder) {
						let nsRange = NSRange(range, in: content)
						if let asRange = Range<AttributedString.Index>(nsRange, in: attributedString) {
							attributedString.replaceSubrange(asRange, with: AttributedString("#\(tag.info.first)"))
						}
						content = content.replacingCharacters(in: range, with: "#\(tag.info.first)")
					}
				}

				// Next, process URLs
				for curHTTPMatch in content.matches(of:urlRegex) {
					let urlString = String(content[curHTTPMatch.range])
					let urlExtension = urlString.split(separator: ".").last?.lowercased()

					if imageExtensions.contains(urlExtension ?? "") {
						imageURL = URL(string: urlString)
						if let asRange = Range<AttributedString.Index>(curHTTPMatch.range, in: attributedString) {
							attributedString.replaceSubrange(asRange, with: AttributedString(""))
						}
					} else {
						if let asAttributedRange = Range<AttributedString.Index>(curHTTPMatch.range, in: attributedString) {
							attributedString[asAttributedRange].foregroundColor = .blue
							attributedString[asAttributedRange].underlineStyle = .thick
						}
					}
				}

				return .success((attributedString, imageURL))
			} catch let error {
				return .failure(error)
			}
		}

		
		var body: some View {
				VStack(alignment: .leading) {
					Group {
						switch renderRichText() {
						case .success(let (richText, imageURL)):
							Text(richText)
								.font(.body)
								.foregroundColor(.primary)
								.multilineTextAlignment(.leading)
							
							if let imageURL = imageURL {
								AsyncImage(url: imageURL) { image in
									image.resizable().aspectRatio(contentMode: .fit)
								} placeholder: {
									ProgressView()
								}
							}
						case .failure:
							Text(event.content) // Fallback to plain text if rich text rendering fails
						}
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
