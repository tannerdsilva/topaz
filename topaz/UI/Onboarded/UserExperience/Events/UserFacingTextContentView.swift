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
			case image(URL)
			case hashtag(String, AttributedString)
		}
		struct SegmentView: View {
			let dbux:DBUX
			var segment: Segment

			var body: some View {
				switch segment {
				case .text(let content, let attributedContent):
					Text(attributedContent)
						.font(.body)
						.foregroundColor(.primary)
						.multilineTextAlignment(.leading)
				case .url(let url, _):
					if let url = URL(string: url) {
						Link(url.absoluteString, destination: url)
							.font(.body)
							.foregroundColor(.blue)
							.underline()
					}
				case .hashtag(let hashtag, let attributedHashtag):
					Text(attributedHashtag)
						.font(.body)
						.foregroundColor(.primary)
				case .image(let imgURL):
					UI.Images.AssetPipeline.AsyncImage(url: imgURL, actor: dbux.unstoredImageActor, content: { image in
						image.resizable()
							.scaledToFill()
					}, placeholder: {
						Text("loading")
					})
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
				
				
				var segments: [Segment] = []

				var currentWord: String = ""
				var currentAttributedString: AttributedString = AttributedString("")
				
				for character in content {
					if character.isWhitespace {
						if !currentWord.isEmpty {
							processWord(&currentWord, &currentAttributedString, &segments, urlRegex)
						}
					} else {
						currentWord.append(character)
						currentAttributedString.append(AttributedString(String(character)))
					}
				}
				
				// Process last word
				if !currentWord.isEmpty {
					processWord(&currentWord, &currentAttributedString, &segments, urlRegex)
				}
				
				return .success(segments)
			} catch let error {
				return .failure(error)
			}
		}



		private func processWord(_ word: inout String, _ attributedWord: inout AttributedString, _ segments: inout [Segment], _ urlRegex:Regex<AnyRegexOutput>) {
			// Check if word is a URL
			
			if let urlMatch = word.firstMatch(of: urlRegex), let url = URL(string: String(word[urlMatch.range])) {
				let urlExtension = url.pathExtension.lowercased()
				let imageExtensions = Set(["jpg", "jpeg", "png", "gif"])
				if imageExtensions.contains(urlExtension) {
					// Handle image URLs if needed
					attributedWord = AttributedString("")
				} else {
					attributedWord.foregroundColor = .blue
					attributedWord.underlineStyle = .thick
				}
				if imageExtensions.contains(urlExtension) {
					segments.append(.image(url))
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
		
		func consolidatedRT() -> Result<[Segment], Swift.Error> {
			switch renderRichText() {
			case .success(let segments):
				var segs = [Segment]()
				var curString = AttributedString()
				for curSeg in segments {
					switch curSeg {
					case .text(_, let attText):
						curString += attText
					case .hashtag(_, let getURL):
						curString += getURL
					default:
						if curString.description.count > 0 {
							segs.append(.text("", curString))
							curString = AttributedString()
						}
						segs.append(curSeg)
					}
				}
				if curString.description.count > 0 {
					segs.append(.text("", curString))
					curString = AttributedString()
				}
				return .success(segs)
			case .failure(let err):
				return .failure(err)
			}
		}
		
		var body: some View {
			Group() {
				switch consolidatedRT() {
				case .success(let segments):
					ForEach(segments, id: \.self) { segment in
						SegmentView(dbux: dbux, segment: segment)
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
