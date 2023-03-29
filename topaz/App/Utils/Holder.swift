//
//  Holder.swift
//  topaz
//
//  Created by Tanner Silva on 3/25/23.
//

import Foundation

// The Holder is a simple class that allows for the holding of elements until a certain amount of time has passed.
// It generally helps group an aggressive stream of incoming elements into more digestible chunks for the database and UI, both of which write with a single thread.
// This tool is deployed by the holder of a relay connection.
internal actor Holder<T>: AsyncSequence {
	typealias Element = [T]
	typealias AsyncIterator = HolderEventStream

	// the elements that are being held
	private var elements: [T] = []
	// the amount of time that must pass before the elements are flushed
	private let holdInterval: TimeInterval
	// the last time the elements were flushed
	private var lastFlush: Date? = nil
	// the consumers of the AsyncSequence that are waiting for the next set of elements
	private var waiters: [UnsafeContinuation<[T]?, Never>] = []

	// initialize the holder with a hold interval
	init(holdInterval: TimeInterval) {
		self.holdInterval = holdInterval
	}

	nonisolated func makeAsyncIterator() -> HolderEventStream {
		return HolderEventStream(holder: self)
	}

	struct HolderEventStream: AsyncIteratorProtocol {
		let holder: Holder
		typealias Element = [T]

		func next() async throws -> [T]? {
			await holder.waitForNext()
		}
	}

	func append(element: T) {
		self.elements.append(element)
		if lastFlush == nil {
			lastFlush = Date()
		}
		flushElementsIfNeeded()
	}

	private func hasTimeThresholdPassed() -> Bool {
		guard let lastFlush = lastFlush else { return false }
		return abs(lastFlush.timeIntervalSinceNow) > holdInterval
	}

	private func flushElementsIfNeeded() {
		if hasTimeThresholdPassed() && !waiters.isEmpty {
			let currentElements = elements
			elements.removeAll()
			lastFlush = Date()

			for waiter in waiters {
				waiter.resume(returning: currentElements)
			}
			waiters.removeAll()
		}
	}

	private func waitForNext() async -> [T]? {
		if hasTimeThresholdPassed() {
			let currentElements = elements
			elements.removeAll()
			lastFlush = Date()
			return currentElements
		} else {
			return await withUnsafeContinuation { continuation in
				waiters.append(continuation)
			}
		}
	}
}
