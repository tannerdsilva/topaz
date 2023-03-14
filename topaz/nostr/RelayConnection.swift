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
    /// the errors that can be thrown by a relay connection interface
	enum Error:Swift.Error {
        /// the interface was in an invalid state for the requested operation
		case invalidState

        /// kinda stupid to have this here but it is here nonetheless
        case encodingError
	}

    /// the default event loop group used for all relay connections (unless otherwise specified for a particular connection)
    public static let defaultPool = MultiThreadedEventLoopGroup(numberOfThreads:System.coreCount)

    /// the logger used by all relay connections
    public let logger:Logger

    /// the events that can be passed to the relay connection handler
	public enum Event {
        /// the connection state has changed
        case stateChange(RelayConnection, RelayConnection.State)
        /// the connection has received a valid handshake message
        case pingPong(RelayConnection)
        /// the connection has received a nostr message
        case event(RelayConnection, nostr.Event)
        /// the connection received a message that could not be parsed
		case garbage(RelayConnection, Data, Swift.Error)
    }

    /// The various states that a relay connection can be in
	public enum State {
        /// There is no connection to the relay
		case disconnected
        /// There is a connection attempt in progress
		case connecting
        /// There is an active connection to the relay
		case connected
	}

    /// the multi-threaded event loop group used for this connection
    fileprivate let loopGroup:MultiThreadedEventLoopGroup = RelayConnection.defaultPool

    /// the websocket connection to the relay (if it exists)
	/// - assumed to never be nil when state == ``State/connected(_:)``
    fileprivate var websocket:HBWebSocket? = nil

    /// the url of the relay connection
    public let url:String

	/// the time to wait before attempting to reconnect to the relay after a connection is closed
	public var reconnectionDelayTimeNanoseconds:UInt64 = 30_000_000_000 // (default: 30 seconds)

    /// the state of the relay connection
    @Published public private(set) var state:State = .disconnected

	fileprivate let outChannel:AsyncChannel<Event>

    /// whether or not the instance should ignore user requests to reconnect to the relay
    /// - when `true`, the connection will NEVER reconnect to the relay after a connection is closed
    fileprivate var reconnectOverride:Bool = false
	
    /// the deferred task that is used to reconnect to the relay after a connection is closed (or upon initialization)
	fileprivate var reconnectionTask:Task<(), Swift.Error>?
	
	fileprivate let encoder = JSONEncoder()

    /// initialize a new relay connection. the connection will be started immediately.
    init(url:String, channel:AsyncChannel<Event>) {
        self.url = url
        self.logger = Logger(label: "relay-ctx")
        self.outChannel = channel
        // connect to the relay in the background
		self.reconnectionTask = Task.detached { [weak self] in
            guard let self = self else { return }
            try await self.connect(retryLaterIfFailed:true) // start the connection
        }
    }

    /// called internally when the websocket connection is closed. this will attempt to reconnect to the relay after a delay
    fileprivate func websocketWasClosed(retry:Bool = true) {
        // ensure that the connection is in the correct state
		guard case .connected = self.state else { return }
        self.logger.debug("disconnected from relay.", metadata: ["url": "\(url)"])
        
        // update the state to reflect the disconnection
        self.websocket = nil
        self.state = .disconnected
        if let hasReconnectionTask = self.reconnectionTask {
            hasReconnectionTask.cancel()
            self.reconnectionTask = nil
        }
        // launch a task to reconnect to the relay if specified to do so
        guard reconnectOverride == true || retry == true else { return }
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
		guard case State.disconnected = self.state else {
			self.logger.error("unable to connect to relay - state was not 'disconnected'.", metadata:["state":"\(self.state)"])
			throw Error.invalidState
		}
        enum StreamEvent {
            case data(Data)
            case pingPong
        }
        do {
            // attempt to connect
            self.state = .connecting
            let newURL = HBURL(self.url)
			let newWS = try await HBWebSocketClient.connect(url:newURL, configuration: HBWebSocketClient.Configuration(), on:loopGroup.next())
			newWS.initiateAutoPing(interval:.seconds(Int64.random(in:7..<12)))   // ensure the state of the connection is always checked
			self.state = .connected
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
				newWS.onClose { [sc = streamCont] _ in
					sc.finish()
					self.logger.trace("async stream finished.")
				}
			}
			
            if let hasReconnectionTask = self.reconnectionTask {
                hasReconnectionTask.cancel()
                self.reconnectionTask = nil
            }
            self.websocket = newWS
            
			Task.detached { [weak self, chan = self.outChannel, ms = mainStream, reconn = retryLaterIfFailed] in
				guard let self = self else {
					return
				}
				let decoder = JSONDecoder()
				for await curItem in ms {
					switch curItem {
					case let .data(capData):
						do {
							let decoded = try decoder.decode(nostr.Event.self, from:capData)
							await chan.send(.event(self, decoded))
						} catch let error {
							self.logger.error("unable to parse nostr event.", metadata:["error":"\(error)"])
						}
					case .pingPong:
						await chan.send(.pingPong(self))
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
	func send(_ req:nostr.Request) async throws {
        // validate the state
		guard case .connected = self.state, let hasSocket = self.websocket else {
            self.logger.error("unable to send request - not currently connected.", metadata:["req":"\(req)"])
            throw Error.invalidState
        }
        
        // write the request
		try await hasSocket.write(.binary(ByteBuffer(data: try encoder.encode(req)))).get()
	}

    /// forces a closure of the connection to the relay and will ensure that the connection is not re-established
    func forceClosure() async throws {
        // validate the state
		guard case .connected = self.state, let hasSocket = self.websocket else {
            self.logger.error("unable to force close connection - not currently connected.", metadata:["state":"\(self.state)"])
            throw Error.invalidState
        }
        self.reconnectOverride = true
        // close the connection
        try await hasSocket.close().get()
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
