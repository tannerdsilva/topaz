//
//  CGSize.swift
//  topaz
//
//  Created by Tanner Silva on 4/25/23.
//

import Foundation

extension CGSize {
	static func * (lhs: CGSize, rhs: CGPoint) -> CGPoint {
		CGPoint(x: lhs.width * rhs.x, y: lhs.height * rhs.y)
	}
}
