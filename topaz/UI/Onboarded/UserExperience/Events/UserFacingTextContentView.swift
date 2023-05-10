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
		let dbux:DBUX
		let event: nostr.Event
		enum Segment: Hashable {
			case text(String, AttributedString)
			case url(String, AttributedString)
			case hashtag(String, AttributedString)
			case newline
		}
		struct SegmentView: View {
			var segment: Segment

			var body: some View {
				switch segment {
				case .text(let content, let attributedContent):
					Text(attributedContent)
						.font(.body)
						.foregroundColor(.primary)
						.multilineTextAlignment(.leading).border(.red)
				case .url(let url, _):
					if let url = URL(string: url) {
						Link(url.absoluteString, destination: url)
							.font(.body)
							.foregroundColor(.blue)
							.underline().border(.red)
					}
				case .hashtag(let hashtag, let attributedHashtag):
					Text(attributedHashtag)
						.font(.body)
						.foregroundColor(.primary).border(.red)
				case .newline:
					Text("").border(.red).background(.yellow)
				}
			}
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

		private func renderRichText() -> Result<[Segment], Swift.Error> {
			do {
				var content: String = event.content
				let urlRegex = try Regex("(https?://[\\w-]+(\\.[\\w-]+)+([\\w.,@?^=%&:/~+#-]*[\\w@?^=%&/~+#-])?)")
				let imageExtensions = ["jpg", "jpeg", "png", "gif"]
				
				var segments: [Segment] = []

				var currentWord: String = ""
				var currentAttributedString: AttributedString = AttributedString("")
				var wasPreviousCharacterNewline = false
				
				for character in content {
					if character.isWhitespace {
						if !currentWord.isEmpty {
							processWord(&currentWord, &currentAttributedString, &segments, urlRegex, imageExtensions)
						}
						
						if character.isNewline && !wasPreviousCharacterNewline {
							segments.append(.newline)
							wasPreviousCharacterNewline = true
						} else if !character.isNewline {
							wasPreviousCharacterNewline = false
						}
					} else {
						currentWord.append(character)
						currentAttributedString.append(AttributedString(String(character)))
						wasPreviousCharacterNewline = false
					}
				}
				
				// Process last word
				if !currentWord.isEmpty {
					processWord(&currentWord, &currentAttributedString, &segments, urlRegex, imageExtensions)
				}
				
				return .success(segments)
			} catch let error {
				return .failure(error)
			}
		}



		private func processWord(_ word: inout String, _ attributedWord: inout AttributedString, _ segments: inout [Segment], _ urlRegex:Regex<AnyRegexOutput>, _ imageExtensions: [String]) {
			// Check if word is a URL
			if let urlMatch = word.firstMatch(of: urlRegex), let url = URL(string: String(word[urlMatch.range])) {
				let urlExtension = url.pathExtension.lowercased()
				
				if imageExtensions.contains(urlExtension) {
					// Handle image URLs if needed
					attributedWord = AttributedString("")
				} else {
					attributedWord.foregroundColor = .blue
					attributedWord.underlineStyle = .thick
				}

				segments.append(.url(word, attributedWord))
			}
			// Check if word is a hashtag
			else if word.hasPrefix("#") {
				attributedWord.foregroundColor = .blue
				segments.append(.hashtag(word, attributedWord))
			}
			// If word is just text
			else {
				if let lastSegment = segments.last, case .text(var previousText, var previousAttributedText) = lastSegment {
					// Add a space before appending the word
					previousText.append(" \(word)")
					previousAttributedText.append(AttributedString(" "))
					previousAttributedText.append(attributedWord)
					segments[segments.count - 1] = .text(previousText, previousAttributedText)
				} else {
					segments.append(.text(word, attributedWord))
				}
			}
			
			// Reset word and attributed word
			word = ""
			attributedWord = AttributedString("")
		}
		
		var body: some View {
			VStack(alignment: .leading) {
				switch renderRichText() {
				case .success(let segments):
					ForEach(segments, id: \.self) { segment in
						SegmentView(segment: segment)
					}
				case .failure:
					Text(event.content).border(.green) // Fallback to plain text if rich text rendering fails
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
