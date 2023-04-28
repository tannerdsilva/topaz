//
//  topazApp.swift
//  topaz
//
//  Created by Tanner Silva on 3/4/23.
//

import SwiftUI
import QuickLMDB
import Logging
import SystemPackage
import NIO

@main
struct Topaz:App, Based {
	struct Account:Hashable, Identifiable {
		var id:nostr.Key {
			get {
				return key
			}
		}
		let key:nostr.Key
		let profile:nostr.Profile
		
		static func == (lhs:Account, rhs:Account) -> Bool {
			return lhs.key == rhs.key
		}
		
		func hash(into hasher:inout Hasher) {
			hasher.combine(self.key)
		}
	}
	enum Error:Swift.Error {
		case systemReadError
		case memoryAllocationError
	}
	public static let defaultRelays:Set<Relay> = Set([
		Relay("wss://relay.snort.social"),
		Relay("wss://relay.damus.io"),
		Relay("wss://welcome.nostr.wine")
	])
	
	/// the default event loop group used for all relay connections (unless otherwise specified for a particular connection)
	public static let defaultPool = MultiThreadedEventLoopGroup(numberOfThreads:System.coreCount)
	public static let applicationDispatcher = Dispatcher<Topaz.Notification>(logLabel:"topaz", logLevel:.info)
	public static let tester_account = try! KeyPair.from(nsec:"nsec1s23j6z0x4w2y35c5zkf6le539sdmkmw4r7mm9jj22gnltrllqxzqjnh2wm")
	
	public static func readSystemSecureData(length:size_t) throws -> Data {
		// open a file descriptor to secure random data
		let fd = try FileDescriptor.open("/dev/random", .readOnly)
		defer {
			try? fd.close()
		}
		// open a buffer to read the secure data into
		guard let readBuffer = malloc(length) else {
			throw Error.memoryAllocationError
		}
		defer {
			free(readBuffer)
		}
		// read the data, and make sure all 128 bytes have been read
		guard read(fd.rawValue, readBuffer, length) == length else {
			throw Error.systemReadError
		}
		return Data(bytes:readBuffer, count:length)
	}
	
	static func findApplicationBase() throws -> URL {
		try FileManager.default.url(for:.libraryDirectory, in: .userDomainMask, appropriateFor:nil, create:true)
	}
	
	static func launchExperienceEngine<T>(_ type: T.Type, from base: URL, for publicKey: nostr.Key, dispatcher:Dispatcher<T.NotificationType>) throws -> T where T: ExperienceEngine {
		let isDirectory = type.env_flags.contains(.noSubDir) ? false : true
		let path = base.appendingPathComponent(type.name, isDirectory: isDirectory)

		if isDirectory {
			try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: nil)
			let dataMdbPath = path.appendingPathComponent("data.mdb")
			let increaseSize = size_t(dataMdbPath.getFileSize()) + size_t(type.deltaSize)
			let makeEnv = try QuickLMDB.Environment(path: path.path, flags: type.env_flags, mapSize: increaseSize, maxDBs: type.maxDBs)
			return try type.init(base: path, env: makeEnv, publicKey: publicKey, dispatcher: dispatcher)
		} else {
			let increaseSize = size_t(path.getFileSize()) + size_t(type.deltaSize)
			let makeEnv = try QuickLMDB.Environment(path: path.path, flags: type.env_flags, mapSize: increaseSize, maxDBs: type.maxDBs)
			return try type.init(base: path, env: makeEnv, publicKey: publicKey, dispatcher: dispatcher)
		}
	}
	
	static func launchSharedExperienceEngine<T>(_ type: T.Type, base:URL, env environment:QuickLMDB.Environment, for publicKey: nostr.Key, dispatcher:Dispatcher<T.NotificationType>) throws -> T where T:SharedExperienceEngine {
		return try type.init(env:environment, publicKey:publicKey, dispatcher:dispatcher)
	}

	
	public static func makeDefaultLogger(label:String) -> Logger {
		var logger = Logger(label:label)
		#if DEBUG
		logger.logLevel = .info
		#else
		logger.logLevel = .notice
		#endif
		return logger
	}
	static let logger = makeDefaultLogger(label:"topaz-app")
	
	fileprivate static func initializeEnvironment(url:URL, flags:QuickLMDB.Environment.Flags) -> Result<QuickLMDB.Environment, Swift.Error> {
		do {
			if FileManager.default.fileExists(atPath:url.path) == false {
				try FileManager.default.createDirectory(at:url, withIntermediateDirectories:true)
			}
			let env = try QuickLMDB.Environment(path:url.path, flags:flags, mapSize:size_t(5e8))
			Self.logger.debug("successfully opened LMDB environment.", metadata:["path":"\(url.path)"])
			return .success(env)
		} catch let error {
			Self.logger.error("failed to open LMDB environment.", metadata:["error":"\(error)"])
			return .failure(error)
		}
	}

	static func openLMDBEnv(named:String, flags:QuickLMDB.Environment.Flags = [.noTLS, .noSync, .noReadAhead]) -> Result<QuickLMDB.Environment, Swift.Error> {
		do {
			let homePath = try FileManager.default.url(for:.libraryDirectory, in: .userDomainMask, appropriateFor:nil, create:true).appendingPathComponent(named, isDirectory:true)
			return Self.initializeEnvironment(url: homePath, flags:flags)
		} catch let error {
			return .failure(error)
		}
	}
	
	let base = try! Self.findApplicationBase()
	
	@ObservedObject var localData:ApplicationModel
	
	init() {
		do {
			let appModel = try Topaz.launchExperienceEngine(ApplicationModel.self, from:self.base, for:nostr.Key.nullKey(), dispatcher:Self.applicationDispatcher)
			_localData = ObservedObject(wrappedValue: appModel)
		} catch _ {
			fatalError("false")
		}
	}

    var body: some Scene {
        WindowGroup {
			ContentView(appData: localData)
        }
    }
}



extension Topaz {
	enum Notification:Hashable {
		case userProfileInfoUpdated
	}
}
