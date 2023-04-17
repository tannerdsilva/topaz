//
//  Dispatcher.swift
//  topaz
//
//  Created by Tanner Silva on 4/14/23.
//

import Logging

actor Dispatcher<T:Hashable> {
	let logger:Logger
	typealias Event = T
	typealias EventHandler = (T) -> Void
	
	private var listeners: [T: [UInt32: EventHandler]] = [:]

	init(logLabel:String, logLevel:Logger.Level) {
		let makeLogger = Logger(label:"dispatcher-\(logLabel)")
		self.logger = makeLogger
	}
		
	func addListener(forEventType eventType: T, _ handler: @escaping EventHandler) -> UInt32 {
		let id = UInt32.random(in: 0..<UInt32.max)
		if listeners[eventType] == nil {
			listeners[eventType] = [id:handler]
		} else {
			var getExisting = listeners[eventType]!
			getExisting[id] = handler
			listeners[eventType] = getExisting
		}
		return id
	}

	func removeListener(forEventType eventType: T, _ id: UInt32) {
		if var hasListeners = listeners[eventType] {
			hasListeners.removeValue(forKey: id)
			listeners[eventType] = hasListeners
		}
	}

	func fireEvent(_ event: T) {
		if let eventTypeListeners = listeners[event] {
			for (_, listener) in eventTypeListeners {
				listener(event)
			}
		}
	}
}
