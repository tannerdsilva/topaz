//
//  String.swift
//  topaz
//
//  Created by Tanner Silva on 5/6/23.
//

import Foundation

extension String {
	var noEmoji: String {
		return self.unicodeScalars
			.filter { !$0.properties.isEmoji }
			.filter { !$0.isWhitespace }
			.string
	}
}

extension Sequence where Iterator.Element == UnicodeScalar {
	var string: String {
		return String(String.UnicodeScalarView(self))
	}
}

