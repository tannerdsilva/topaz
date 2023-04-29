//
//  Holder.swift
//  topaz
//
//  Created by Tanner Silva on 3/25/23.
//
// The Holder is a simple class that allows for the holding of elements until a certain amount of time has passed.
// It generally helps group an aggressive stream of incoming elements into more digestible chunks for the database and UI, both of which write with a single thread.
// This tool is deployed by the holder of a relay connection.

import Foundation

internal actor Holder<T>: AsyncSequence {
	typealias Element = [T]
	typealias AsyncIterator = HolderEventStream

	private var elements: [T] = []
	private let holdInterval: TimeInterval
	private var lastFlush: timeval? = nil
	private var waiters: [UnsafeContinuation<[T]?, Never>] = []
	private var periodicFlushTask: Task<Void, Never>? = nil
	private var isFinished: Bool = false

	init(holdInterval: TimeInterval) {
		self.holdInterval = holdInterval
		self.periodicFlushTask = Task { [weak self] in
			do {
				while true {
					try await Task.sleep(nanoseconds:UInt64(holdInterval * 1_000_000_000))
					guard let self = self else { return }
					await self.flushElementsIfNeeded()
				}
			} catch {}
		}
	}

	deinit {
		periodicFlushTask?.cancel()
	}

	nonisolated func makeAsyncIterator() -> HolderEventStream {
		return HolderEventStream(holder: self)
	}

	struct HolderEventStream: AsyncIteratorProtocol {
		let holder: Holder
		typealias Element = [T]

		func next() async -> [T]? {
			await holder.waitForNext()
		}
	}

	func append(element: T) {
		self.elements.append(element)
		if lastFlush == nil {
			lastFlush = timeval()
			gettimeofday(&lastFlush!, nil)
		}
		flushElementsIfNeeded()
	}

	private func hasTimeThresholdPassed() -> Bool {
		guard let lastFlush = lastFlush else { return false }
		var currentTime = timeval()
		gettimeofday(&currentTime, nil)
		let elapsedTime = Double(currentTime.tv_sec - lastFlush.tv_sec) + Double(currentTime.tv_usec - lastFlush.tv_usec) / 1_000_000.0
		return elapsedTime > holdInterval
	}

	private func flushElementsIfNeeded() {
		if hasTimeThresholdPassed() && !waiters.isEmpty {
			let currentElements = elements
			elements.removeAll()
			lastFlush = timeval()
			gettimeofday(&lastFlush!, nil)
			for waiter in waiters {
				waiter.resume(returning: currentElements)
			}
			waiters.removeAll()
		}
	}
	
	func finish() {
		isFinished = true
		for waiter in waiters {
			waiter.resume(returning: nil)
		}
		waiters.removeAll()
	}
	
	private func waitForNext() async -> [T]? {
		if isFinished {
			return nil
		}
		
		if hasTimeThresholdPassed() {
			let currentElements = elements
			elements.removeAll()
			lastFlush = timeval()
			gettimeofday(&lastFlush!, nil)
			return currentElements
		} else {
			return await withUnsafeContinuation { continuation in
				if isFinished {
					continuation.resume(returning: nil)
				} else {
					waiters.append(continuation)
				}
			}
		}
	}
}
