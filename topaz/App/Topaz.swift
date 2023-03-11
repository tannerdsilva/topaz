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

@main
struct Topaz:App {
	public static let bootstrap_relays = [
		Relay("wss://relay.damus.io")
	]
	
	public static let tester_account = try! KeyPair.from(nsec:"nsec1s23j6z0x4w2y35c5zkf6le539sdmkmw4r7mm9jj22gnltrllqxzqjnh2wm")
	
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
	
	fileprivate static func initializeEnvironment(url:URL, flags:QuickLMDB.Environment.Flags) -> Result<QuickLMDB.Environment, Error> {
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

	static func openLMDBEnv(named:String, flags:QuickLMDB.Environment.Flags = [.noTLS, .noSync, .noReadAhead]) -> Result<QuickLMDB.Environment, Error> {
		do {
			let homePath = try FileManager.default.url(for:.libraryDirectory, in: .userDomainMask, appropriateFor:nil, create:true).appendingPathComponent(named, isDirectory:true)
			return Self.initializeEnvironment(url: homePath, flags:flags)
		} catch let error {
			return .failure(error)
		}
	}
	
	@StateObject var localData:ApplicationModel
	
	init() {
		do {
			let localData = Topaz.openLMDBEnv(named:"topaz-app")
			switch (localData) {
			case (.success(let localData)):
				let appModel = try ApplicationModel(localData, tx:nil)
				_localData = StateObject(wrappedValue:appModel)
			default:
				fatalError("false")
			}
		} catch let error {
			print("\(error)")
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

