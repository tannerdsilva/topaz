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
import QuickLMDB

/// Primary interface for interacting with a nostr relay
final actor RelayConnection:ObservableObject {
    /// the type of tuple that is passed to the state change event handler
    public typealias StateChangeEvent = (RelayConnection, State)
    /// the type of tuple that is passed to the event handler
	public typealias EventCapture = (String, nostr.Event)
    /// the errors that can be thrown by a relay connection interface
	enum Error:Swift.Error {
        /// the interface was in an invalid state for the requested operation
		case invalidState

        /// kinda stupid to have this here but it is here nonetheless
        case encodingError

        /// the connection was canceled
        case connectionCanceled
	}

    /// the default event loop group used for all relay connections (unless otherwise specified for a particular connection)
    public static let defaultPool = MultiThreadedEventLoopGroup(numberOfThreads:System.coreCount)

    /// the logger used by all relay connections
    public let logger:Logger

    /// The various states that a relay connection can be in
	public enum State:UInt8, MDB_convertible {
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

    fileprivate let stateChannel:AsyncChannel<StateChangeEvent>
    public let holder:EventHolder
    /// whether or not the instance should ignore user requests to reconnect to the relay
    /// - when `true`, the connection will NEVER reconnect to the relay after a connection is closed
    fileprivate var reconnectOverride:Bool = false
    /// the deferred task that is used to reconnect to the relay after a connection is closed (or upon initialization)
	fileprivate var reconnectionTask:Task<(), Swift.Error>?
	fileprivate let encoder = JSONEncoder()

    /// initialize a new relay connection. the connection will be started immediately.
	init(url:String, stateChannel:AsyncChannel<StateChangeEvent>, holder:EventHolder) {
        self.url = url
        var logger = Logger(label: "relay-ctx")
		logger.logLevel = .trace
		self.logger = logger
		self.stateChannel = stateChannel
        self.holder = holder
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
                try? await newWS.close().get()
				await self.websocketWasClosed(retry:false)
                return
            }
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
				newWS.onClose { [sc = streamCont] _ in
					sc.finish()
					self.logger.trace("async stream finished.")
				}
			}
			
            // cancel the reconnection task if it exists
            if let hasReconnectionTask = self.reconnectionTask {
                hasReconnectionTask.cancel()
                self.reconnectionTask = nil
            }
            self.websocket = newWS
            
            // launch the task that handles the data as it comes off the async stream
			Task.detached { [weak self, ho = holder, ms = mainStream, reconn = retryLaterIfFailed] in
				// ensure that the connection is in the correct state
                guard let self = self else {
					return
				}
				let decoder = JSONDecoder()
				for await curItem in ms {
					switch curItem {
					case let .data(capData):
						do {
							let decoded = try decoder.decode(nostr.Event.self, from:capData)
							await ho.append(event:decoded)
						} catch let error {
							self.logger.error("unable to parse nostr event.", metadata:["error":"\(error)"])
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
}

// MARK: - EventHolder
extension RelayConnection {
    // the event holder is a simple class that allows for the holding of events until a certain amount of time has passed.
    // it generally helps group an agressive stream of incoming events into more digestable chunks for the database and UI
    // this tool is deployed by the holder of a relay connection.
    internal actor EventHolder:AsyncSequence {
        nonisolated func makeAsyncIterator() -> EventHolderEventStream {
            return EventHolderEventStream(holder:self)
        }
        
        typealias AsyncIterator = EventHolderEventStream
        typealias Element = [nostr.Event]
        struct EventHolderEventStream:AsyncIteratorProtocol {
            let holder:EventHolder
            func next() async throws -> [nostr.Event]? {
                await holder.waitForNext()
            }
            
            typealias Element = [nostr.Event]
        }
        
        private var events = [nostr.Event]()
        
        init(holdInterval:TimeInterval) {
            self.holdInterval = holdInterval
        }
        func append(event:nostr.Event) {
            self.events.append(event)
            if self.hasTimeThresholdPassed() == true && waiters.count > 0 {
                for curFlush in self.waiters {
                    curFlush.resume(returning:self.events)
                }
                self.waiters.removeAll()
                self.events.removeAll()
            }
        }
        
        let holdInterval:TimeInterval
        private var lastFlush:Date? = nil
        private var waiters = [UnsafeContinuation<[nostr.Event]?, Never>]()
        private func hasTimeThresholdPassed() -> Bool {
            if (abs(lastFlush!.timeIntervalSinceNow) > holdInterval) {
                return true
            } else {
                return false
            }
        }
        private func waitForNext() async -> [nostr.Event]? {
            func flushIt() -> [nostr.Event]? {
                defer {
                    self.events.removeAll()
                    self.lastFlush = Date()
                }
                return self.events
            }
            func waitItOut() async -> [nostr.Event]? {
                return await withUnsafeContinuation({ waitCont in
                    self.waiters.append(waitCont)
                })
            }
            if lastFlush == nil {
                // time limit does not apply
                if (self.events.count > 0) {
                    return flushIt()
                } else {
                    return await waitItOut()
                }
            } else {
                switch self.hasTimeThresholdPassed() {
                case true:
                    if self.events.count > 0 {
                        return flushIt()
                    } else {
                        return await waitItOut()
                    }
                case false:
                    return await waitItOut()
                }
            }
        }
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
