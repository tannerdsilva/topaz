//
//  Dispatcher.swift
//  topaz
//
//  Created by Tanner Silva on 4/14/23.
//

actor Dispatcher<T:Hashable> {
	typealias Event = T
	typealias EventHandler = (T) -> Void
	
	private var listeners: [T: [UInt32: EventHandler]] = [:]

	func addListener(forEventType eventType: T, _ handler: @escaping EventHandler) -> UInt32 {
		let id = UInt32.random(in: 0..<UInt32.max)
		if listeners[eventType] == nil {
			listeners[eventType] = [:]
		}
		listeners[eventType]?[id] = handler
		return id
	}

	func removeListener(forEventType eventType: T, _ id: UInt32) {
		listeners[eventType]?.removeValue(forKey: id)
	}

	func fireEvent(_ event: T) async {
		if let eventTypeListeners = listeners[event] {
			for (_, listener) in eventTypeListeners {
				listener(event)
			}
		}
	}
}
