//
//  String.swift
//  topaz
//
//  Created by Tanner Silva on 5/6/23.
//

import Foundation

extension String {
	var noEmoji: String {
		let noEmoString = self.unicodeScalars
			.filter { !$0.properties.isEmoji }
			.string
		return noEmoString.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

extension Sequence where Iterator.Element == UnicodeScalar {
	var string: String {
		return String(String.UnicodeScalarView(self))
	}
}
