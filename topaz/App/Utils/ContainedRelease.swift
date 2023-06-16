//
//  ContainedRelease.swift
//  topaz
//
//  Created by Tanner Silva on 5/11/23.
//

import Foundation

class ContainedRelease<T> {
	typealias ReleaseAction = (T) async -> Void
	public let containedValue:T
	public let releaseAction:ReleaseAction
	
	public init(containedValue:T, _ releaseAction:@escaping(ReleaseAction)) {
		self.containedValue = containedValue
		self.releaseAction = releaseAction
	}
	
	deinit {
		Task.detached { [cv = containedValue, ra = releaseAction] in
			await ra(cv)
		}
	}
}
