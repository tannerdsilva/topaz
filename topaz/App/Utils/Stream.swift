//
//  Stream.swift
//  topaz
//
//  Created by Tanner Silva on 3/17/23.
//

import Foundation

struct Stream<T> {
	let stream:AsyncStream<T>
	let continuation:AsyncStream<T>.Continuation

	init() {
		var getContinuation:AsyncStream<T>.Continuation? = nil
		let newStream = AsyncStream<T> { (continuation) in
			getContinuation = continuation
		}
		self.stream = newStream
		self.continuation = getContinuation!
	}
}
