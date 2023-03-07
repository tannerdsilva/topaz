////
////  NostrConnection.swift
////  damus
////
////  Created by William Casarin on 2022-04-02.
////
//
//import Foundation
//import Hummingbird
//import HummingbirdWSCore
//import HummingbirdWSClient
//import NIO
//import Logging
//
///// Primary interface for interacting with a nostr relay
//final actor RelayConnection:ObservableObject {
//    /// the errors that can be thrown by a relay connection interface
//	enum Error:Swift.Error {
//        /// the interface was in an invalid state for the requested operation
//		case invalidState
//
//        /// kinda stupid to have this here but it is here nonetheless
//        case encodingError
//	}
//
//    /// the default event loop group used for all relay connections (unless otherwise specified for a particular connection)
//    public static let defaultPool = MultiThreadedEventLoopGroup(numberOfThreads:System.coreCount)
//
//    /// the logger used by all relay connections
//    public static var logger = Logger(label: "relay-ctx")
//
//    /// the event handler type that relay connections use to pass events to the caller
//    public typealias Handler = (Event) -> Void
//
//    /// The various states that a relay connection can be in
//	public enum State:UInt8 {
//        /// There is no connection to the relay
//		case disconnected = 0
//        /// There is a connection attempt in progress
//		case connecting = 1
//        /// There is an active connection to the relay
//		case connected = 2
//	}
//
//    /// Events that can be passed to the relay connection handler
//    public enum Event {
//        /// the connection state has changed
//        case stateChange(State)
//        /// the connection has received a binary message
//        case data(Data)
//        /// the connection has received a text message
//        case text(String)
//    }
//
//    /// the multi-threaded event loop group used for this connection
//    fileprivate let loopGroup:MultiThreadedEventLoopGroup = RelayConnection.defaultPool
//
//    /// the websocket connection to the relay (if it exists)
//	/// - assumed to never be nil when state == ``State/disconnected``
//    fileprivate var websocket:HBWebSocket? = nil
//
//    /// the url of the relay connection
//    public let url:String
//
//	/// the time to wait before attempting to reconnect to the relay after a connection is closed
//	public var reconnectionDelayTimeNanoseconds:UInt64 = 30_000_000_000 // (default: 30 seconds)
//
//    /// the state of the relay connection
//    @Published public private(set) var state:State = .disconnected {
//        didSet {
//            self.handler(.stateChange(self.state))
//        }
//    }
//
//    /// the event handler for this connection
//    fileprivate let handler:Handler
//
//    /// whether or not the instance should ignore user requests to reconnect to the relay
//    /// - when `true`, the connection will NEVER reconnect to the relay after a connection is closed
//    fileprivate var reconnectOverride:Bool = false
//	
//    /// the deferred task that is used to reconnect to the relay after a connection is closed (or upon initialization)
//	fileprivate var reconnectionTask:Task<(), Swift.Error>? = nil
//
//    /// initialize a new relay connection. the connection will be started immediately.
//    init(url:String, _ handler:@escaping Handler) {
//        self.url = url
//        self.handler = handler
//
//        // connect to the relay in the background
//        self.reconnectionTask = Task.detached { [weak self] in
//            guard let self = self else { return }
//            try await self.connect(retryLaterIfFailed:true) // start the connection
//        }
//    }
//
//    /// called internally when the websocket connection is closed. this will attempt to reconnect to the relay after a delay
//    fileprivate func websocketWasClosed(retry:Bool = true) {
//        // ensure that the connection is in the correct state
//        guard self.state == .connected else { return }
//        Self.logger.debug("disconnected from relay.", metadata: ["url": "\(url)"])
//        
//        // update the state to reflect the disconnection
//        self.websocket = nil
//        self.state = .disconnected
//        if let hasReconnectionTask = self.reconnectionTask {
//            hasReconnectionTask.cancel()
//            self.reconnectionTask = nil
//        }
//        // launch a task to reconnect to the relay if specified to do so
//        guard reconnectOverride == true || retry == true else { return }
//        self.reconnectionTask = Task.detached { [weak self, time = reconnectionDelayTimeNanoseconds, reconn = retry] in
//            // sleep for the configured amount of time
//            try await Task.sleep(nanoseconds:time)
//
//            // attempt to reconnect
//            guard let self = self else { return }
//            try await self.connect(retryLaterIfFailed:reconn)
//        }
//    }
//
//    /// connects to the relay. this will attempt to reconnect to the relay if the connection fails, unless `retryLaterIfFailed` is false
//    /// - will only connect if the connection is in the ``State/disconnected`` state
//    func connect(retryLaterIfFailed:Bool = true) async throws {
//		guard self.state == .disconnected else {
//			Self.logger.error("unable to connect to relay - state was not 'disconnected'.", metadata:["state":"\(self.state)"])
//			throw Error.invalidState
//		}
//        do {
//            // attempt to connect
//            self.state = .connecting
//            let newURL = HBURL(self.url)
//			let newWS = try await HBWebSocketClient.connect(url:newURL, configuration: HBWebSocketClient.Configuration(), on:loopGroup.next())
//			newWS.initiateAutoPing(interval:.seconds(10))   // ensure the state of the connection is always checked
//            
//            // if not throwing, then we have a connection. update the internal state
//            self.state = .connected
//            if let hasReconnectionTask = self.reconnectionTask {
//                hasReconnectionTask.cancel()
//                self.reconnectionTask = nil
//            }
//            self.websocket = newWS
//            
//            // handle reading 
//            newWS.onRead { [hndlr = handler] readInfo, _ in
//                switch readInfo {
//                case var .binary(byteBuff):
//                    if let hasData = byteBuff.readData(length:byteBuff.readableBytes) {
//                        hndlr(.data(hasData))
//                    } else {
//                        Self.logger.debug("unable to read data from websocket.", metadata:["readInfo":"\(readInfo)", "url":"\(self.url)"])
//                    }
//                case let .text(stringInfo):
//                    hndlr(.text(stringInfo))
//                }
//            }
//            // handle closing
//            newWS.onClose { [weak self, reconn = retryLaterIfFailed] _ in
//                Task.detached { [weak self] in
//                    guard let self = self else { return }
//                    await self.websocketWasClosed(retry:reconn)
//                }
//            }
//        } catch let error {
//			Self.logger.error("unable to connect to relay.", metadata:["url":"\(self.url)", "error":"\(error)"])
//            // update the state to reflect the disconnection
//			self.state = .disconnected
//            self.websocket = nil
//            if let hasReconnectionTask = self.reconnectionTask {
//                hasReconnectionTask.cancel()
//                self.reconnectionTask = nil
//            }
//
//            // launch a new task to reconnect to the relay if specified to do so
//            if retryLaterIfFailed {
//                self.reconnectionTask = Task.detached { [weak self, time = reconnectionDelayTimeNanoseconds] in
//                    // sleep for the configured amount of time
//                    try await Task.sleep(nanoseconds:time)
//
//                    // attempt to reconnect
//                    guard let self = self else { return }
//                    try await self.connect(retryLaterIfFailed:retryLaterIfFailed)
//                }
//            }
//        }
//    }
//	
//    /// send a request to the relay
//    /// - Throws: 
//    ///     - `Error.encodingError` if the request could not be encoded (this is dumb and should be changed maybe)
//    ///     - `Error.invalidState` if the connection was not in a valid state to send the request
//    ///     - may possibly throw other errors from the underlying websocket library
//	func send(_ req:NostrRequest) async throws {
//        // validate the state
//        guard self.state == .connected, let hasSocket = self.websocket else {
//            Self.logger.error("unable to send request - not currently connected.", metadata:["req":"\(req)"])
//            throw Error.invalidState
//        }
//
//        // encode the request
//		guard let req = make_nostr_req(req) else {
//            Self.logger.error("unable to encode nostr request.", metadata:["req":"\(req)"])
//			throw Error.encodingError
//		}
//        
//        // write the request
//		try await hasSocket.write(.text(req)).get()
//	}
//
//    /// forces a closure of the connection to the relay and will ensure that the connection is not re-established
//    func forceClosure() async throws {
//        // validate the state
//        guard self.state == .connected, let hasSocket = self.websocket else {
//            Self.logger.error("unable to force close connection - not currently connected.", metadata:["state":"\(self.state)"])
//            throw Error.invalidState
//        }
//        self.reconnectOverride = true
//        // close the connection
//        try await hasSocket.close().get()
//    }
//}
//
//// MARK: - RelayConnection & Equatable
//extension RelayConnection:Equatable {
//    static func == (lhs: RelayConnection, rhs: RelayConnection) -> Bool {
//        return lhs.url == rhs.url
//    }
//}
//
//// MARK: - RelayConnection & Hashable
//extension RelayConnection:Hashable {
//    nonisolated func hash(into hasher: inout Hasher) {
//        hasher.combine(url)
//    }
//}
//
////
////final class RelayConnection {
////    private(set) var isConnected = false
////    private(set) var isConnecting = false
////    private(set) var isReconnecting = false
////
////    private(set) var last_connection_attempt: TimeInterval = 0
////    private lazy var socket = {
////        let req = URLRequest(url: url)
////        let socket = WebSocket(request: req, compressionHandler: .none)
////        socket.delegate = self
////        return socket
////    }()
////    private var handleEvent: (NostrConnectionEvent) -> ()
////    private let url: URL
////
////    init(url: URL, handleEvent: @escaping (NostrConnectionEvent) -> ()) {
////        self.url = url
////        self.handleEvent = handleEvent
////    }
////
////    func reconnect() {
////        if isConnected {
////            isReconnecting = true
////            disconnect()
////        } else {
////            // we're already disconnected, so just connect
////            connect(force: true)
////        }
////    }
////
////    func connect(force: Bool = false) {
////        if !force && (isConnected || isConnecting) {
////            return
////        }
////
////        isConnecting = true
////        last_connection_attempt = Date().timeIntervalSince1970
////        socket.connect()
////    }
////
////    func disconnect() {
////        socket.disconnect()
////        isConnected = false
////        isConnecting = false
////    }
////
////    func send(_ req: NostrRequest) {
////        guard let req = make_nostr_req(req) else {
////            print("failed to encode nostr req: \(req)")
////            return
////        }
////
////        socket.write(string: req)
////    }
////
////    // MARK: - WebSocketDelegate
////
////    func didReceive(event: WebSocketEvent, client: WebSocket) {
////        switch event {
////        case .connected:
////            self.isConnected = true
////            self.isConnecting = false
////
////        case .disconnected:
////            self.isConnecting = false
////            self.isConnected = false
////            if self.isReconnecting {
////                self.isReconnecting = false
////                self.connect()
////            }
////
////        case .cancelled, .error:
////            self.isConnecting = false
////            self.isConnected = false
////
////        case .text(let txt):
////            if txt.count > 2000 {
////                DispatchQueue.global(qos: .default).async {
////                    if let ev = decode_nostr_event(txt: txt) {
////                        DispatchQueue.main.async {
////                            self.handleEvent(.nostr_event(ev))
////                        }
////                        return
////                    }
////                }
////            } else {
////                if let ev = decode_nostr_event(txt: txt) {
////                    handleEvent(.nostr_event(ev))
////                    return
////                }
////            }
////
////            print("decode failed for \(txt)")
////            // TODO: trigger event error
////
////        default:
////            break
////        }
////
////        handleEvent(.ws_event(event))
////    }
////}
//
//func make_nostr_req(_ req: NostrRequest) -> String? {
//    switch req {
//    case .subscribe(let sub):
//        return make_nostr_subscription_req(sub.filters, sub_id: sub.sub_id)
//    case .unsubscribe(let sub_id):
//        return make_nostr_unsubscribe_req(sub_id)
//    case .event(let ev):
//        return make_nostr_push_event(ev: ev)
//    }
//}
//
//func make_nostr_push_event(ev: NostrEvent) -> String? {
//    guard let event = encode_json(ev) else {
//        return nil
//    }
//    let encoded = "[\"EVENT\",\(event)]"
//    print(encoded)
//    return encoded
//}
//
//func make_nostr_unsubscribe_req(_ sub_id: String) -> String? {
//    "[\"CLOSE\",\"\(sub_id)\"]"
//}
//
//func make_nostr_subscription_req(_ filters: [NostrFilter], sub_id: String) -> String? {
//    let encoder = JSONEncoder()
//    var req = "[\"REQ\",\"\(sub_id)\""
//    for filter in filters {
//        req += ","
//        guard let filter_json = try? encoder.encode(filter) else {
//            return nil
//        }
//        let filter_json_str = String(decoding: filter_json, as: UTF8.self)
//        req += filter_json_str
//    }
//    req += "]"
//    return req
//}
