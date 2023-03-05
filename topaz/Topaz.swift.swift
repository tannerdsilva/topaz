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
	public static func makeDefaultLogger(label:String) -> Logger {
		var logger = Logger(label:label)
		#if DEBUG
		logger.logLevel = .info
		#else
		logger.logLevel = .notice
		#endif
		return logger
	}
	
	static func initializeMainEnvironment(url:URL, flags:QuickLMDB.Environment.Flags) -> Result<QuickLMDB.Environment, Error> {
		do {
			let homePath = url.appendingPathComponent("topaz-appinuiii", isDirectory:true)
			if FileManager.default.fileExists(atPath: homePath.path) == false {
				try FileManager.default.createDirectory(at:homePath, withIntermediateDirectories:true)
			}
			let env = try QuickLMDB.Environment(path:homePath.path, flags:flags)
			return .success(env)
		} catch let error {
			return .failure(error)
		}
	}
	
	let localData:ApplicationModel.Metadata
	
	init() {
		do {
			let localData = Topaz.initializeMainEnvironment(url:try! FileManager.default.url(for:.libraryDirectory, in: .userDomainMask, appropriateFor:nil, create:true), flags:[.noTLS, .noSync, .noReadAhead])
			switch (localData) {
			case (.success(let localData)):
				self.localData = try ApplicationModel.Metadata(localData, tx:nil)
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
			ContentView(appData:localData)
        }
    }
}
