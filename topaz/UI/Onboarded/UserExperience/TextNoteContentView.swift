import SwiftUI

struct TextNoteContentView: View {
	let content: String
	
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
