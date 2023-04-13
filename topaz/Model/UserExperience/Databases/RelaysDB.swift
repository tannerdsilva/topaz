//
//  RelaysDB.swift
//  topaz
//
//  Created by Tanner Silva on 3/17/23.
//

import Foundation
import QuickLMDB
import Logging
import SwiftBlake2
import AsyncAlgorithms

extension UE {
	// the primary database for managing relays and their connections
	class RelaysDB:ObservableObject {
		// produces the shortened "relayHash" for 
		private static func produceRelayHash<B>(url:B) throws -> Data where B:ContiguousBytes {
			var newHasher = try Blake2bHasher(outputLength:8)
			try newHasher.update(url)
			return try newHasher.export()
		}
		
		enum Databases:String {
			// related to profiles and their listed relays
			case pubkey_relays_asof = "pubkey-relays-asof"
			case pubkey_relayHash = "pubkey-relayHash"
			case relayHash_pubKey = "relayHash-pubKey"
			case relayHash_relayString = "relayHash-relayString"

			// related to connections and data exchange
			case relayHash_relayConnection = "relayHash-relayConnection"
			case relayHash_status = "relayHash-status"

			// related to relay state information
			case relayHash_pendingEvents = "relayHash-pendingEvents"
			case relayHash_currentSubscriptions = "relayHash-currentSubscriptions"
		}
		
		fileprivate let logger:Logger
		fileprivate let env:QuickLMDB.Environment
		let myPubkey:String

		// related to profiles and their listed relays
		private let pubkey_relays_asof:Database		// stores the last time the user updated their profile							[String:DBUX.Date]
		private let pubkey_relayHash:Database		// stores the list of relay hashes that the user has listed in their profile	[String:String] * DUP *
		private let relayHash_relayString:Database	// stores the full relay URL for a given relay hash								[String:String]
		private let relayHash_pubKey:Database		// stores the public key for a given relay hash									[String:String] * DUP *
		
		// related to the actual connection to the relay
		private let relayHash_relayConnection:Database // stores the connection for a given relay hash								[String:RelayConnection] (object database)
		private let relayHash_relayState:Database	// stores the state of a given relay hash										[String:RelayConnection.State]
		
		// related to relay state information
		private let relayHash_currentSubscriptions:Database // stores the current subscriptions for a given relay hash					[String:[nostr.Subscribe]]
		private let relayHash_pendingEvents:Database // stores the pending events for a given relay hash								[String:[nostr.Event]]

		// stores the relay connections for the current user
		@MainActor @Published public private(set) var userRelayConnections:[String:RelayConnection]
		// stores the relay connection states for the current user
		@MainActor @Published public private(set) var userRelayConnectionStates:[String:RelayConnection.State]

		let holder:Holder<nostr.Event>
		
		private let eventChannel:AsyncChannel<RelayConnection.EventCapture>
		private let stateChannel:AsyncChannel<RelayConnection.StateChangeEvent>
		private var digestTask:Task<Void, Never>? = nil

		init(base:URL, pubkey:String) throws {
			
			self.myPubkey = pubkey
			let newHolder = Holder<nostr.Event>(holdInterval:0.25)
			self.holder = newHolder
			let targetURL = base.appendingPathComponent("ux-relays.mdb", isDirectory:false)
			let envSize:size_t = size_t(targetURL.getFileSize()) + size_t(1e+9)
			let env = try QuickLMDB.Environment(path:targetURL.path, flags:[.noSubDir], mapSize:envSize, maxDBs:8)
			self.env = env
			
			var newLogger = Logger(label:"ux-relays.mdb")
			newLogger.logLevel = .debug
			
			let subTrans = try Transaction(env, readOnly:false)
			let pubkeyRelaysAsofDB = try env.openDatabase(named:Databases.pubkey_relays_asof.rawValue, flags:[.create], tx:subTrans)
			let pubRelaysDB = try env.openDatabase(named:Databases.pubkey_relayHash.rawValue, flags:[.create, .dupSort], tx:subTrans)
			let relayStringDB = try env.openDatabase(named:Databases.relayHash_relayString.rawValue, flags:[.create], tx:subTrans)
			let relayConnectionDB = try env.openDatabase(named:Databases.relayHash_relayConnection.rawValue, flags:[.create], tx:subTrans)
			let relayStatusDB = try env.openDatabase(named:Databases.relayHash_status.rawValue, flags:[.create], tx:subTrans)
			let relayPendingDB = try env.openDatabase(named:Databases.relayHash_pendingEvents.rawValue, flags:[.create], tx:subTrans)
			let relaySubscriptionsDB = try env.openDatabase(named:Databases.relayHash_currentSubscriptions.rawValue, flags:[.create], tx:subTrans)
			do {
				try relayConnectionDB.deleteAllEntries(tx:subTrans)
				try relayStatusDB.deleteAllEntries(tx:subTrans)
				try relaySubscriptionsDB.deleteAllEntries(tx:subTrans)
			} catch LMDBError.notFound {}
			let pubRelaysCursor = try pubRelaysDB.cursor(tx:subTrans)
			let relayStringCursor = try relayStringDB.cursor(tx:subTrans)
			let relayStatusCursor = try relayStatusDB.cursor(tx:subTrans)
			let eventC = AsyncChannel<RelayConnection.EventCapture>()
			let stateC = AsyncChannel<RelayConnection.StateChangeEvent>()
			self.eventChannel = eventC
			self.stateChannel = stateC
			self.logger = newLogger
			self.pubkey_relays_asof = pubkeyRelaysAsofDB
			self.pubkey_relayHash = pubRelaysDB
			self.relayHash_relayString = relayStringDB
			self.relayHash_relayConnection = relayConnectionDB
			self.relayHash_relayState = relayStatusDB
			self.relayHash_pendingEvents = relayPendingDB
			self.relayHash_currentSubscriptions = relaySubscriptionsDB
			self.relayHash_pubKey = try env.openDatabase(named:Databases.relayHash_pubKey.rawValue, flags:[.create, .dupSort], tx:subTrans)
			
			// check for the relays that the current user has listed in their profile
			let getRelays:Set<String>
			do {
				let iterator = try pubRelaysCursor.makeDupIterator(key: pubkey)
				var buildStrings = Set<String>()

				for (_, curRelayHash) in iterator {
					let relayString = try relayStringCursor.getEntry(.set, key:curRelayHash).value
					buildStrings.update(with:String(relayString)!)
				}
				getRelays = buildStrings
			} catch LMDBError.notFound {
				// the user does not have any relays yet, so we'll add the default ones
				let relays = Set(Topaz.defaultRelays.compactMap({ $0.url }))
				for curRelay in relays {
					let relayHash = try RelaysDB.produceRelayHash(url:Data(curRelay.utf8))
					try relayStringCursor.setEntry(value:curRelay, forKey:relayHash)
					try pubRelaysCursor.setEntry(value:relayHash, forKey:pubkey)
					try self.relayHash_pubKey.setEntry(value:pubkey, forKey:relayHash, tx:subTrans)
				}
				getRelays = relays
			}
			var buildConnections = [String:RelayConnection]()
			var buildStates = [String:RelayConnection.State]()
			for curRelay in getRelays {
				let newConnection = RelayConnection(url:curRelay, stateChannel:stateC, eventChannel:eventC)
				let relayHash = try RelaysDB.produceRelayHash(url:Data(curRelay.utf8))
//				try relayConnectionDB.setObject(value:newConnection, forKey:relayHash, tx:subTrans)
//				newLogger.info("then connection retain value: \(_getRetainCount(newConnection))")
//				let oldRetain = _getRetainCount(newConnection)
//				newLogger.info("then connection retain value: \(_getRetainCount(newConnection))")
//				let relayGet = try relayConnectionDB.getObject(type:RelayConnection.self, forKey:relayHash, tx:subTrans)!
//				newLogger.info("then connection retain value: \(_getRetainCount(newConnection))")
//				let relayGet2 = try relayConnectionDB.getObject(type:RelayConnection.self, forKey:relayHash, tx:subTrans)!
//				let newretain = _getRetainCount(relayGet)
				buildConnections[curRelay] = newConnection
//				newLogger.info("RETAIN VALUE", metadata:["1":"\(oldRetain)", "2":"\(newretain)"])
				
				buildStates[curRelay] = .disconnected
				
				try relayStatusCursor.setEntry(value:RelayConnection.State.disconnected, forKey:relayHash)
				try relaySubscriptionsDB.setEntry(value:[] as [nostr.Subscribe], forKey: pubkey, tx:subTrans)
			}
			_userRelayConnections = Published(wrappedValue:buildConnections)
			_userRelayConnectionStates = Published(initialValue:buildStates)
			try subTrans.commit()
			
			// launch the digest task
			self.digestTask = Task.detached { [weak self, sc = stateC, newEnv = env, logThing = newLogger, eventC = eventC] in
				await withThrowingTaskGroup(of:Void.self, body: { [weak self, sc = sc, newEnv = newEnv, ec = eventC] tg in
					// status
					tg.addTask { [weak self, sc = sc, newEnv = newEnv] in
						guard let self = self else { return }
						for await (curChanger, newState) in sc {
							let relayHash = try Self.produceRelayHash(url:Data(curChanger.url.utf8))
							let newTrans = try Transaction(newEnv, readOnly:false)
							if newState == .connected {
								let getSubs = try self.relayHash_currentSubscriptions.getEntry(type:[nostr.Subscribe].self, forKey:relayHash, tx:newTrans)!
								for curSub in getSubs {
									do {
										try await curChanger.send(.subscribe(curSub))
									} catch let error {
										logThing.critical("there was a problem writing the message to the relay", metadata:["error":"\(error)"])
									}
								}
							}
							self.relayConnectionStatusUpdated(relay:curChanger.url, state:newState)
							logThing.trace("successfully updated relay connection state \(newState)", metadata:["url":"\(curChanger.url)"])
							try newTrans.commit()
						}
					}
					
					// events
					tg.addTask { [weak self, ec = ec] in
						guard let self = self else { return }
						for await curEvent in ec {
							switch curEvent.1 {
							case let .event(subID, myEvent):
								logThing.trace("got event.", metadata:["kind":"\(myEvent.kind.rawValue)", "pubkey":"\(myEvent.pubkey)"])
								await self.holder.append(element: myEvent)
								break;
							case .endOfStoredEvents(let subID):
								logThing.trace("end of events", metadata:["sub_id":"\(subID)"])
								break;
							default:
								break;
							}
						}
					}
				})
			}
		}
		
		// an internal function that an instance calls upon itself to update the relay connection state
		fileprivate func relayConnectionStatusUpdated(relay:String, state:RelayConnection.State) {
			Task.detached { @MainActor [weak self, relay = relay, state = state] in
				guard let self = self else { return }
				self.userRelayConnectionStates[relay] = state
			}
		}

		// gets the relays for a given pubkey
		//  - throws LMDBError.notFound if the pubkey is not found
		func getRelays(pubkey:String) throws -> Set<String> {
			try env.transact(readOnly:true) { someTrans in
				var buildRelays = Set<String>()
				let relayHashCursor = try self.pubkey_relayHash.cursor(tx:someTrans)
				let relayStringCursor = try self.relayHash_relayString.cursor(tx:someTrans)
				for (_, curRelayHash) in try relayHashCursor.makeDupIterator(key:pubkey) {
					let relayString = try relayStringCursor.getEntry(.set, key:curRelayHash).value
					buildRelays.update(with:String(relayString)!)
				}
				return buildRelays
			}
		}

		// sets the relays for a given pubkey
		//  - if the relay information is already in the database, LDMBError.keyExists will be thrown
		func setRelays(_ relays:Set<String>, pubkey:String, asOf writeDate:DBUX.Date) throws {
			#if DEBUG
			self.logger.critical("attempting to assign \(relays.count) relays for pubkey \(pubkey) as of \(writeDate.exportDate())")
			#endif
			let newTrans = try Transaction(self.env, readOnly:false)
			do {
				let checkDate = try self.pubkey_relays_asof.getEntry(type:DBUX.Date.self, forKey:pubkey, tx:newTrans)!
				guard checkDate < writeDate else {
					#if DEBUG
					self.logger.critical("attempted to write relay information for pubkey \(pubkey) that was older than the existing information", metadata:["existing":"\(checkDate.exportDate())", "new":"\(writeDate.exportDate())"])
					#endif
					newTrans.abort()
					if (checkDate != writeDate) {
						throw LMDBError.keyExists
					} else {
						return
					}
				}
			} catch LMDBError.notFound {
				#if DEBUG
				self.logger.critical("assigning new relay list based on event date \(writeDate.exportDate()) for pubkey \(pubkey)")
				#endif
			}
			try self.pubkey_relays_asof.setEntry(value:writeDate, forKey:pubkey, tx:newTrans)
			var didModify = false
			
			// hash-pubkey associations
			let relayHashCursor = try self.pubkey_relayHash.cursor(tx:newTrans)
			let relayHashPubKeyCursor = try self.relayHash_pubKey.cursor(tx:newTrans)
			
			let relayStringCursor = try self.relayHash_relayString.cursor(tx:newTrans)
			let relayStateCursor = try self.relayHash_relayState.cursor(tx:newTrans)

			let relaySubsCursor = try self.relayHash_currentSubscriptions.cursor(tx:newTrans)
			let relayEventsCursor = try self.relayHash_pendingEvents.cursor(tx:newTrans)
			
			var removeConnections = Set<String>()

			var assignRelays = relays
			do {
				// iterate through all existing entries and determine if they need to be removed from the database
				for (_ , curRelayHash) in try relayHashCursor.makeDupIterator(key:pubkey) {
					// check if the relay is still in the list of relays that we are setting
					let relayStringVal = try relayStringCursor.getEntry(.set, key:curRelayHash).value
					let relayString = String(relayStringVal)!
					self.logger.critical("evaluating relay that already exists in db", metadata:["name":"\(relayString)"])
					if !assignRelays.contains(relayString) {
						didModify = true
						self.logger.critical("relay should NOT be retained", metadata:["name":"\(relayString)"])
						// check if there are any other public keys that are using this relay
						do {
							try relayHashPubKeyCursor.getEntry(.getBoth, key:curRelayHash, value:pubkey)
							let relayHashPubKeyCount = try relayHashPubKeyCursor.dupCount()
							if relayHashPubKeyCount == 1 {
								// this is the only public key that is using this relay, so we can remove it from the database
								// - remove the relay connection object
								do {
									try self.relayHash_relayConnection.deleteObject(type:RelayConnection.self, forKey:curRelayHash, tx:newTrans)
								} catch LMDBError.notFound {}
								// - remove the public key associations
								try relayHashPubKeyCursor.deleteEntry()
								try relayHashCursor.deleteEntry()
								// - remove the actual URL string
								try relayStringCursor.deleteEntry()
								// - remove the state
								try relayStateCursor.getEntry(.set, key:curRelayHash)
								try relayStateCursor.deleteEntry()
								// - remove any pending subscriptions
								try relaySubsCursor.getEntry(.set, key:curRelayHash)
								try relaySubsCursor.deleteEntry()
								// - remove any pending events
								try relayEventsCursor.getEntry(.set, key:curRelayHash)
								try relayEventsCursor.deleteEntry()
								removeConnections.update(with: relayString)
							} else {
								// there are other public keys that are using this relay, so we can just remove the public key from the list of public keys that are using this relay
								try relayHashPubKeyCursor.deleteEntry()
								try relayHashCursor.deleteEntry()
								removeConnections.update(with: relayString)
							}
						} catch LMDBError.notFound {
							self.logger.critical("notfound thrown")
							// this should never happen, but if it does, we can just remove the relay from the database
							// - remove the relay connection object
							do {
								try self.relayHash_relayConnection.deleteObject(type:RelayConnection.self, forKey:curRelayHash, tx:newTrans)
							} catch LMDBError.notFound {}
							// - remove the public key associations
							try relayHashPubKeyCursor.deleteEntry()
							try relayHashCursor.deleteEntry()
							// - remove the actual URL string
							try relayStringCursor.deleteEntry()
							// - remove the relay state
							try relayStateCursor.getEntry(.set, key:curRelayHash)
							try relayStateCursor.deleteEntry()
							// - remove any pending subscriptions
							try relaySubsCursor.getEntry(.set, key:curRelayHash)
							try relaySubsCursor.deleteEntry()
							// - remove any pending events
							try relayEventsCursor.getEntry(.set, key:curRelayHash)
							try relayEventsCursor.deleteEntry()
							removeConnections.update(with: relayString)
						}
					} else {
						// remove the relay from the list of relays that we are setting
						assignRelays.remove(relayString)
						self.logger.critical("relay should be retained", metadata:["name":"\(relayString)"])
					}
				}
			} catch LMDBError.notFound {}
			var buildConnections = [String:RelayConnection]()
			var buildStates = [String:RelayConnection.State]()
			// iterate through the list of relays that we are setting and add them to the database
			for curRelay in assignRelays {
				let curRelayHash = try RelaysDB.produceRelayHash(url:Data(curRelay.utf8))
				try relayHashCursor.setEntry(value:curRelayHash, forKey:pubkey)
				try relayHashPubKeyCursor.setEntry(value:pubkey, forKey:curRelayHash)
				try relayStringCursor.setEntry(value:curRelay, forKey:curRelayHash)
				try relayStateCursor.setEntry(value:RelayConnection.State.disconnected, forKey:curRelayHash)
				try relaySubsCursor.setEntry(value:([] as [nostr.Subscription]), forKey:curRelayHash)
				try relayEventsCursor.setEntry(value:([] as [nostr.Event]), forKey:curRelayHash)
				if pubkey == myPubkey {
					let newRelayConnection = RelayConnection(url:curRelay, stateChannel:stateChannel, eventChannel:eventChannel)
//					try self.relayHash_relayConnection.setObject(value:newRelayConnection, forKey:curRelayHash, tx:newTrans)
					try relayStateCursor.setEntry(value:RelayConnection.State.disconnected, forKey:curRelayHash)
					buildStates[curRelay] = RelayConnection.State.disconnected
					buildConnections[curRelay] = newRelayConnection
				}
			}
			if assignRelays.count > 0 {
				didModify = true
			}

			// if these are the relays that belong to the current user, manage the current connections so that they can become an updated list of connections
			if pubkey == myPubkey {
				if didModify == true {
					Task.detached { @MainActor [weak self, buildConns = buildConnections, buildStates = buildStates, removes = removeConnections] in
						guard let self = self else {
							return
						}
						var editConns = self.userRelayConnections
						var editStates = self.userRelayConnectionStates
						for curRM in removes {
							if let getconn = editConns.removeValue(forKey:curRM) {
								Task.detached { [conn = getconn] in
									try await conn.forceClosure()
								}
							}
							editStates.removeValue(forKey:curRM)
						}
						for curAdd in buildConns {
							editConns[curAdd.key] = curAdd.value
						}
						for curAddState in buildStates {
							editStates[curAddState.key] = curAddState.value
						}
						self.userRelayConnections = editConns
						self.userRelayConnectionStates = editStates
					}
				}
			}
			self.logger.critical("successfully set relays for public key.", metadata:["relay_count":"\(assignRelays.count)", "did_modify":"\(didModify)", "pubkey":"\(pubkey)"])
			try newTrans.commit()
		}

		func getConnection(relay url:String) throws -> RelayConnection {
			let newConnection = try self.relayHash_relayConnection.getObject(type:RelayConnection.self, forKey:try Self.produceRelayHash(url:Data(url.utf8)), tx:nil)!
			return newConnection
		}

		func add(subscriptions:[nostr.Subscribe], to relayURL:String) throws {
			let newTransaction = try Transaction(self.env, readOnly:false)
			let relayHash = try Self.produceRelayHash(url:Data(relayURL.utf8))
			let relaySubscriptionsCursor = try self.relayHash_currentSubscriptions.cursor(tx:newTransaction)
			// load the existing subscriptions
			var currentSubscriptions:Array<nostr.Subscribe>
			do {
				currentSubscriptions = Array<nostr.Subscribe>(try relaySubscriptionsCursor.getEntry(.set, key:relayHash).value)!
			} catch _ {
				currentSubscriptions = []
			}
			currentSubscriptions.append(contentsOf:subscriptions)
			try relaySubscriptionsCursor.setEntry(value:currentSubscriptions, forKey:relayHash)
			
			// check if this relay is connected, and if it is, send the subscriptions to the relay
			let checkStatus = try self.relayHash_relayState.getEntry(type:RelayConnection.State.self, forKey:relayHash, tx:newTransaction)!
			if checkStatus == .connected {
				let relayConnection = try self.getConnection(relay:relayURL)
				try newTransaction.commit()
				Task.detached { [rc = relayConnection] in
					for curSub in subscriptions {
						try await rc.send(.subscribe(curSub))
					}
				}
			} else {
				try newTransaction.commit()
			}
		}
	}
}
