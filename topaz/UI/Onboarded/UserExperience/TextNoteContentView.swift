import SwiftUI

struct TextNoteContentView: View {
	let content: String

//	private var richText: AttributedString {
//		var attributedString = AttributedString(content)
//		let urlPattern = "((https|http)://)((\\w|-)+)(([.]|[/])((\\w|-)+))+"
//		let hashtagPattern = "#[\\p{L}0-9_]*"
//
//		let fullPattern = "(\(urlPattern)|\(hashtagPattern))"
//		let regex = try? NSRegularExpression(pattern: fullPattern, options: [])
//
//		if let regex = regex {
//			let matches = regex.matches(in: content)
//			for match in matches {
//				if let range = Range(match.range, in: content) {
//					let specialText = String(content[range])
//
//					if specialText.starts(with: "http") {
//						attributedString[range].foregroundColor = .blue
//						attributedString[range].underlineStyle = .thick
//					} else {
//						attributedString[range].foregroundColor = .purple
//					}
//				}
//			}
//		}
//
//		return attributedString
//	}

	
	var body: some View {
		Text(content)
	}
}

enum ContentSegment: Hashable {
	case text(String)
	case url(String)
	case hashtag(String)
}

extension NSRegularExpression {
	func matches(in string: String) -> [NSTextCheckingResult] {
		let nsRange = NSRange(string.startIndex..<string.endIndex, in: string)
		return matches(in: string, options: [], range: nsRange)
	}
}
