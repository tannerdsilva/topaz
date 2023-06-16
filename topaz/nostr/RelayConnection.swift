//
//  RelayConnection.swift
//  topaz
//
//  Created by Tanner Silva on 03-2023.
//

import Foundation
import Hummingbird
import HummingbirdWSCore
import HummingbirdWSClient
import NIO
import Logging
import AsyncAlgorithms

/// Primary interface for interacting with a nostr relay
final actor RelayConnection:ObservableObject {
    /// the type of tuple that is passed to the state change event handler
    public typealias StateChangeEvent = (RelayConnection, State)
    /// the type of tuple that is passed to the event handler
	public typealias EventCapture = (String, nostr.Subscription)
	/// the type of typle tht is passed to the subscription change event handler
	public typealias SubscriptionChangeEvent = (RelayConnection, Set<String>, Set<String>)

    /// the errors that can be thrown by a relay connection interface
	enum Error:Swift.Error {
        /// the interface was in an invalid state for the requested operation
		case invalidState

        /// kinda stupid to have this here but it is here nonetheless
        case encodingError

        /// the connection was canceled
        case connectionCanceled
	}

    /// the logger used by all relay connections
    public let logger:Logger

    /// The various states that a relay connection can be in
	public enum State:UInt8 {
        /// There is no connection to the relay
		case disconnected
        /// There is a connection attempt in progress
		case connecting
        /// There is an active connection to the relay
		case connected
	}
	
	let kp:nostr.KeyPair
	
    /// the multi-threaded event loop group used for this connection
    fileprivate let loopGroup:MultiThreadedEventLoopGroup = Topaz.defaultPool

    /// the websocket connection to the relay (if it exists)
	/// - assumed to never be nil when state == ``State/connected(_:)``
    fileprivate var websocket:HBWebSocket? = nil

    /// the url of the relay connection
    nonisolated public let url:String

	/// the time to wait before attempting to reconnect to the relay after a connection is closed
	public var reconnectionDelayTimeNanoseconds:UInt64 = 30_000_000_000 // (default: 30 seconds)

    /// the state of the relay connection
    public private(set) var state:State = .disconnected {
		didSet {
			self.logger.info("state changed to 'disconnected'.")
			switch state {
			case .disconnected:
				self.clearAllSubs()
			default:
				break;
			}
		}
	}
	/// events are written here
	fileprivate let eventChannel:AsyncChannel<EventCapture>
	/// state changes are written here
    fileprivate let stateChannel:AsyncChannel<StateChangeEvent>
	/// subscription changes are written here
	fileprivate let subscriptionChangeChannel:AsyncChannel<SubscriptionChangeEvent>

    /// whether or not the instance should ignore user requests to reconnect to the relay
    /// - when `true`, the connection will NEVER reconnect to the relay after a connection is closed
    fileprivate var reconnectOverride:Bool = false

    /// the deferred task that is used to reconnect to the relay after a connection is closed (or upon initialization)
	fileprivate var reconnectionTask:Task<(), Swift.Error>?

	fileprivate let encoder = JSONEncoder()
	
	// sync state
	fileprivate var subFilters = [String:Set<nostr.Filter>]()
	fileprivate var subs = Set<String>()
	fileprivate var eoses = Set<String>()

	// clears all subscriptions
	private func clearAllSubs() {
		let oldSubs = self.subs
		let oldEOS = self.eoses
		self.subs = Set<String>()
		self.eoses = Set<String>()
		self.subFilters = [String:Set<nostr.Filter>]()
		self.logger.info("cleared all subscriptions.")
	}

	// documents that a new subscription was written out to the relay
	func wroteSub(_ name:String, filters:Set<nostr.Filter>) async {
		let oldSubs = self.subs
		let oldEOS = self.eoses
		if let hasExistingValue = self.subFilters[name] {
			guard hasExistingValue != filters else {
				// return if the filters are the same, this is a no-op
				self.logger.info("subscription '\(name)' already exists with the same filters.")
				return
			}
		}
		self.subs.update(with:name)
		self.subFilters[name] = filters
		if eoses.contains(name) {
			eoses.remove(name)
		}
		self.logger.info("wrote subscription '\(name)' to relay.")
		if self.subs != oldSubs || self.eoses != oldEOS {
			await self.subscriptionChangeChannel.send((self, self.subs, self.eoses))
		}
		
	}

	func gotEOSE(_ name:String) async {
		let oldEOSes = self.eoses
		self.eoses.update(with:name)
		self.logger.info("got EOS for subscription '\(name)'.")
		if oldEOSes != self.eoses {
			await self.subscriptionChangeChannel.send((self, self.subs, self.eoses))
		}
	}

	func removeSub(_ name:String) async {
		let oldSubs = self.subs
		let oldEOS = self.eoses
		self.subFilters.removeValue(forKey:name)
		self.subs.remove(name)
		self.eoses.remove(name)
		self.logger.info("removed subscription '\(name)' from relay.")
		if self.subs != oldSubs || self.eoses != oldEOS {
			await self.subscriptionChangeChannel.send((self, self.subs, self.eoses))
		}
	}

    /// initialize a new relay connection. the connection will be started immediately.
	init(kp:nostr.KeyPair, url:String, stateChannel:AsyncChannel<StateChangeEvent>, eventChannel:AsyncChannel<EventCapture>, subscriptionChannel:AsyncChannel<SubscriptionChangeEvent>) {
        self.url = url
		self.kp = kp
        var logger = Logger(label: "relay-ctx")
		logger.logLevel = .trace
		self.logger = logger
		self.stateChannel = stateChannel
        self.eventChannel = eventChannel
		self.subscriptionChangeChannel = subscriptionChannel
        // connect to the relay in the background
		self.reconnectionTask = Task.detached { [weak self] in
            guard let self = self else { return }
            try await self.connect(retryLaterIfFailed:true) // start the connection
        }
    }

    /// called internally when the websocket connection is closed. this will attempt to reconnect to the relay after a delay
    fileprivate func websocketWasClosed(retry:Bool = true) async {
        // ensure that the connection is in the correct state
		guard case .connected = self.state else { return }
        self.logger.info("disconnected from relay.", metadata: ["url": "\(url)"])
        
        // update the state to reflect the disconnection
        self.websocket = nil
        self.state = .disconnected
		if let hasReconnectionTask = self.reconnectionTask {
			hasReconnectionTask.cancel()
			self.reconnectionTask = nil
		}
		await stateChannel.send((self, .disconnected))
        // launch a task to reconnect to the relay if specified to do so
        guard retry == true && reconnectOverride == false else { return }
        self.reconnectionTask = Task.detached { [weak self, time = reconnectionDelayTimeNanoseconds, reconn = retry] in
            // sleep for the configured amount of time
            try await Task.sleep(nanoseconds:time)

            // attempt to reconnect
            guard let self = self else { return }
            try await self.connect(retryLaterIfFailed:reconn)
        }
    }

    /// connects to the relay. this will attempt to reconnect to the relay if the connection fails, unless `retryLaterIfFailed` is false
    /// - will only connect if the connection is in the ``State/disconnected`` state
    func connect(retryLaterIfFailed:Bool = true) async throws {
        // a connection can only be initiated if the connection is in the disconnected state
		guard case State.disconnected = self.state else {
			self.logger.error("unable to connect to relay - state was not 'disconnected'.", metadata:["state":"\(self.state)"])
			throw Error.invalidState
		}
        // define the stream event type. this is an internal type used to handle the information as it is read from the websocket
        enum StreamEvent {
            case data(Data)
            case pingPong
        }
        do {
            // attempt to connect
            self.state = .connecting
			await self.stateChannel.send((self, .connecting))
            let newURL = HBURL(self.url)
			let newWS = try await HBWebSocketClient.connect(url:newURL, configuration: HBWebSocketClient.Configuration(), on:loopGroup.next())
            // cancel the connection if the state was changed during the connection attempt
			let shouldExit:Bool
			switch self.state {
			case .connecting:
				if (Task.isCancelled == true) {
					shouldExit = true
				} else {
					shouldExit = false
				}
			default:
				shouldExit = true
			}
			guard shouldExit == false else {
                self.logger.debug("connection attempt canceled.", metadata:["url":"\(self.url)"])
                try await newWS.close().get()
                return
            }
			
			self.websocket = newWS
			self.state = .connected
			await self.stateChannel.send((self, .connected))
			newWS.initiateAutoPing(interval:.seconds(Int64.random(in:7..<12)))   // ensure the state of the connection is always checked
			self.logger.info("successfully connected to relay.", metadata:["url":"\(self.url)"])

            // launch the main async stream that takes the data from the websocket and passes it to the relay connection handler
            let mainStream = AsyncStream(StreamEvent.self) { streamCont in
				self.logger.trace("async stream initialized.")
				// handle reading
				newWS.onRead { [sc = streamCont] readInfo, _ in
					switch readInfo {
					case var .binary(byteBuff):
						if let hasData = byteBuff.readData(length:byteBuff.readableBytes) {
							sc.yield(.data(Data(hasData)))
						} else {
							self.logger.debug("unable to read data from websocket.", metadata:["readInfo":"\(readInfo)", "url":"\(self.url)"])
						}
					case let .text(stringInfo):
						sc.yield(.data(Data(stringInfo.utf8)))
					}
				}

                // handle pings
                newWS.onPong { [sc = streamCont] _ in
                    sc.yield(.pingPong)
                }
                
				// handle closing
				newWS.onClose { [sc = streamCont] something in
					sc.finish()
					self.logger.trace("async stream finished.")
				}
			}
			
            // cancel the reconnection task if it exists
            if let hasReconnectionTask = self.reconnectionTask {
                hasReconnectionTask.cancel()
                self.reconnectionTask = nil
            }
            
            // launch the task that handles the data as it comes off the async stream
			Task.detached { [weak self, ms = mainStream, ec = eventChannel, reconn = retryLaterIfFailed] in
				// ensure that the connection is in the correct state
                guard let self = self else {
					return
				}
				let decoder = JSONDecoder()
				for await curItem in ms {
					switch curItem {
					case let .data(capData):
						let someString = String(data:capData, encoding:.utf8)
						do {
							let decodedItem = try decoder.decode(nostr.Subscription.self, from:capData)
							await ec.send((self.url, decodedItem))
							switch decodedItem {
								
							case .endOfStoredEvents(let sub):
								await self.gotEOSE(sub)
								
							case .authentication(let authString):
								
								var buildResponse = nostr.Event()
								buildResponse.kind = .auth_response
								buildResponse.created = DBUX.Date()
								buildResponse.tags = [nostr.Event.Tag(["relay", "ws://nip42.escalante.golf"]), nostr.Event.Tag(["challenge", authString])]
								buildResponse.pubkey = kp.pubkey
								try buildResponse.computeUID()
								try buildResponse.sign(privateKey:kp.privkey)
								
								Task.detached { [br = buildResponse] in
									try await self.send(br)
									print("SEND THE AUTH RESPONSE \(br.uid)")
								}
							default:
								break;
							}
						} catch let error {
							print(someString!)
							self.logger.error("error trying to decode subscription", metadata:["error":"\(error)"])
						}
					case .pingPong:
						break;
					}
				}
				await self.websocketWasClosed(retry:reconn)
			}
        } catch let error {
			self.logger.error("unable to connect to relay.", metadata:["url":"\(self.url)", "error":"\(error)"])
            // update the state to reflect the disconnection
			self.state = .disconnected
            self.websocket = nil
            if let hasReconnectionTask = self.reconnectionTask {
                hasReconnectionTask.cancel()
                self.reconnectionTask = nil
            }

            // launch a new task to reconnect to the relay if specified to do so
            if retryLaterIfFailed {
                self.reconnectionTask = Task.detached { [weak self, time = reconnectionDelayTimeNanoseconds] in
                    // sleep for the configured amount of time
                    try await Task.sleep(nanoseconds:time)

                    // attempt to reconnect
                    guard let self = self else { return }
                    try await self.connect(retryLaterIfFailed:retryLaterIfFailed)
                }
            }
        }
    }
	
    /// send a request to the relay
    /// - Throws:
    ///     - `Error.encodingError` if the request could not be encoded (this is dumb and should be changed maybe)
    ///     - `Error.invalidState` if the connection was not in a valid state to send the request
    ///     - may possibly throw other errors from the underlying websocket library
	func send(_ req:nostr.Subscription) async throws {
        // validate the state
		guard case .connected = self.state, let hasSocket = self.websocket else {
			self.logger.error("unable to send request - not currently connected.", metadata:["state":"\(self.state)", "sock":"\(self.websocket)"])
            throw Error.invalidState
        }
        
		do {
			// write the request
			try await hasSocket.write(.text(String(data: try encoder.encode(req), encoding:.utf8)!)).get()
		} catch let error {
			self.logger.error("failed to send subscription request to relay.", metadata:["url":"\(self.url)", "error":"\(error)"])
		}
		
		switch req {
		case let .subscribe(subEvent):
			await self.wroteSub(subEvent.sub_id, filters:subEvent.filters)
		case let .unsubscribe(unsubString):
			await self.removeSub(unsubString)
		default:
			break;
		}
		
//		await self.updateRelaySyncState()
	}
	
	func send(_ ev:nostr.Event) async throws {
		guard case .connected = self.state, let hasSocket = self.websocket else {
			self.logger.error("unable to send event - not currently connected.", metadata:["state":"\(self.state)", "sock":"\(self.websocket)"])
			throw Error.invalidState
		}
		
		do {
			let getData = try encoder.encode(nostr.Subscription.event("", ev))
			try await hasSocket.write(.text(String(data:getData, encoding:.utf8)!)).get()

		} catch let error {
			self.logger.error("failed to send event to relay.", metadata:["url":"\(self.url)", "error":"\(error)"])
			throw error
		}
	}

    /// forces a closure of the connection to the relay and will ensure that the connection is not re-established
    func forceClosure() async throws {
        switch self.state {
        case .disconnected:
            self.logger.debug("unable to force close connection - already disconnected.", metadata:["url":"\(self.url)"])
            return
        case .connecting:
            self.state = .disconnected
            self.logger.debug("connection attempt canceled.", metadata:["url":"\(self.url)"])
            return
        case .connected:
            guard let hasSocket = self.websocket else {
                self.logger.error("unable to force close connection - not currently connected.", metadata:["state":"\(self.state)"])
                throw Error.invalidState
            }
            self.reconnectOverride = true
            // close the connection
			try await hasSocket.close().get()
        }
    }
	
	deinit {
		self.logger.notice("relayconnection is deinitializing", metadata:["url":"\(self.url)"])
	}
}

// MARK: - RelayConnection & Equatable
extension RelayConnection:Equatable {
    static func == (lhs: RelayConnection, rhs: RelayConnection) -> Bool {
        return lhs.url == rhs.url
    }
}

// MARK: - RelayConnection & Hashable
extension RelayConnection:Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
