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
struct Topaz:App {
	enum Error:Swift.Error {
		case systemReadError
		case memoryAllocationError
	}
	public static let defaultRelays:Set<Relay> = Set([
		Relay("wss://relay.snort.social"),
		Relay("wss://relay.damus.io")
	])
	
	/// the default event loop group used for all relay connections (unless otherwise specified for a particular connection)
	public static let defaultPool = MultiThreadedEventLoopGroup(numberOfThreads:System.coreCount)

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
	
	static func launchExperienceEngine<T>(_ type:T.Type, from base:URL, for publicKey:nostr.Key) throws -> T where T:ExperienceEngine {
		let path = base.appendingPathComponent(type.name, isDirectory:type.env_flags.contains(.noSubDir) ? false : true)
		let increaseSize = size_t(path.getFileSize()) + size_t(type.deltaSize)
		let makeEnv = try QuickLMDB.Environment(path: path.path, flags: type.env_flags, mapSize: increaseSize, maxDBs: type.maxDBs)
		return try type.init(base:path, env: makeEnv, publicKey:publicKey)
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
	
//	static func openOrCreateUX(pubkey:String) -> Result<UX, Swift.Error> {
//		do {
//			let homePath = try FileManager.default.url(for:.libraryDirectory, in: .userDomainMask, appropriateFor:nil, create:true).appendingPathComponent(named, isDirectory:true)
//			
//		}
//	}
	
	@ObservedObject var localData:ApplicationModel
	
	init() {
		do {
			let localData = Topaz.openLMDBEnv(named:"topaz-app")
			switch (localData) {
			case (.success(let localData)):
				let appModel = try ApplicationModel(localData, tx:nil)
				_localData = ObservedObject(wrappedValue: appModel)
			default:
				fatalError("false")
			}
		} catch let error {
			fatalError("false")
		}
	}

    var body: some Scene {
        WindowGroup {
			ContentView(appData: localData)
        }
    }
}


/// returns the username that the calling process is running as
public func getCurrentUser() -> String {
	return String(validatingUTF8:getpwuid(geteuid()).pointee.pw_name)!
}

