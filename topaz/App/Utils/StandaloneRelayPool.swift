//
//  StandaloneRelayPool.swift
//  topaz
//
//  Created by Tanner Silva on 4/24/23.
//

import Foundation
import Foundation
import QuickLMDB
import struct CLMDB.MDB_dbi
import SwiftBlake2
import Logging
import AsyncAlgorithms

// class StandaloneRelayEngine {
// 	let logger:Logger

// 	let mainHolder = Holder<(String, nostr.Event)>(holdInterval:0.25)

// 	@MainActor @Published public private(set) var relayConnections = [String:RelayConnection]()
// 	@MainActor @Published public private(set) var relayConnectionStates = [String:RelayConnection.State]()

// 	@MainActor public func getConnectionsAndStates() -> ([String:RelayConnection], [String:RelayConnection.State]) {
// 		return (relayConnections, relayConnectionStates)
// 	}

// 	private let eventChannel = AsyncChannel<RelayConnection.EventCapture>
// 	private let stateChannel = AsyncChannel<RelayConnection.StateChangeEvent>
// 	private var digestTask:Task<Void, Never>? = nil

// 	init(initialRelays:Set<String>) throws {
// 		var buildConnections = [String:RelayConnection]()
// 		var buildStates = [String:RelayConnection.State]()
// 		for curRelay in getRelays {
// 			let launchConnection = try RelayConnection(relay:curRelay, eventChannel:eventChannel, stateChannel:stateChannel)
// 			buildConnections[curRelay] = launchConnection
// 			buildStates[curRelay] = .disconnected
// 		}
// 		_relayConnections = Published(wrappedValue:buildConnections)
// 		_relayConnectionStates = Published(wrappedValue:buildStates)
// 		// self.digestTask = Task.detached { [weak self, ec = self.eventChannel] in
// 		// 	guard let self = self else { return }
// 		// 	for await curEvent in ec {
// 		// 		switch curEvent.1 {
// 		// 			case let .event(subID, myEvent):

// 		// 			case .endOfStoredEvents(let subID):
// 		// 		}
// 		// 	}

// 		// }
// 	}
// }
