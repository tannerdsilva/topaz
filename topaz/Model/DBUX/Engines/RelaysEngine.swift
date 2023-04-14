//
//  RelaysEngine.swift
//  topaz
//
//  Created by Tanner Silva on 4/13/23.
//

import Foundation
import QuickLMDB
import struct CLMDB.MDB_dbi
import SwiftBlake2
import Logging
import AsyncAlgorithms

extension DBUX {
	class RelayEngine:ObservableObject, ExperienceEngine {
		static let name = "relay-engine.mdb"
		static let deltaSize = size_t(1.9e10)
		static let maxDBs:MDB_dbi = 6
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let base:URL
		let env:QuickLMDB.Environment
		let pubkey:nostr.Key

		let logger:Logger
		
		enum Databases:String {
			case pubkey_relays_asof = "pubkey-relays-asof"							//[nostr.Key:DBUX.Date]
			case pubkey_relayHash = "pubkey-relayHash"								//[nostr.Key:DBUX.RelayHash]
			case relayHash_pubKey = "relayHash-pubKey"								//[DBUX.RelayHash:nostr.Key]
			case relayHash_relayString = "relayHash-relayString"					//[DBUX.RelayHash:String]

			case relayHash_pendingEvents = "relayHash-pendingEvents"				//[Data:[DBUX.Event]]
			case relayHash_currentSubscriptions = "relayHash-currentSubscriptions"	//[Data:[nostr.Subscribe]]
		}

		let holder:Holder<nostr.Event>

		// stores the relay connections for the current user
		@MainActor @Published public private(set) var userRelayConnections = [String:RelayConnection]()
		// stores the relay connection states for the current user
		@MainActor @Published public private(set) var userRelayConnectionStates = [String:RelayConnection.State]()

		private let eventChannel:AsyncChannel<RelayConnection.EventCapture>
		private let stateChannel:AsyncChannel<RelayConnection.StateChangeEvent>
		private var digestTask:Task<Void, Never>? = nil

		let pubkey_relays_asof:Database
		let pubkey_relayHash:Database
		let relayHash_pubKey:Database
		let relayHash_relayString:Database
		
		let relayHash_pendingEvents:Database
		let relayHash_currentSubscriptions:Database
		
		required init(base:URL, env:QuickLMDB.Environment, publicKey:nostr.Key) throws {
			self.base = base
			self.env = env
			self.holder = Holder<nostr.Event>(holdInterval:0.35)
			let newLogger = Topaz.makeDefaultLogger(label:"relay-engine.mdb")
			self.logger = newLogger
			self.pubkey = publicKey
			let subTrans = try Transaction(env, readOnly:false)
			self.pubkey_relays_asof = try env.openDatabase(named:Databases.pubkey_relays_asof.rawValue, flags:[.create], tx:subTrans)
			self.pubkey_relayHash = try env.openDatabase(named:Databases.pubkey_relayHash.rawValue, flags:[.create, .dupSort], tx:subTrans)
			self.relayHash_pubKey = try env.openDatabase(named:Databases.relayHash_pubKey.rawValue, flags:[.create, .dupSort], tx:subTrans)
			self.relayHash_relayString = try env.openDatabase(named:Databases.relayHash_relayString.rawValue, flags:[.create], tx:subTrans)

			self.relayHash_pendingEvents = try env.openDatabase(named:Databases.relayHash_pendingEvents.rawValue, flags:[.create], tx:subTrans)
			self.relayHash_currentSubscriptions = try env.openDatabase(named:Databases.relayHash_currentSubscriptions.rawValue, flags:[.create], tx:subTrans)
			let eventC = AsyncChannel<RelayConnection.EventCapture>()
			let stateC = AsyncChannel<RelayConnection.StateChangeEvent>()
			self.eventChannel = eventC
			self.stateChannel = stateC
			try self.relayHash_currentSubscriptions.deleteAllEntries(tx:subTrans)
			let getRelays:Set<String>
			do {
				let pubRelaysCursor = try self.pubkey_relayHash.cursor(tx:subTrans)
				let iterator = try pubRelaysCursor.makeDupIterator(key:publicKey)
				var buildStrings = Set<String>()
				for (_, curRelayHash) in iterator {
					let getRelayString = try relayHash_relayString.getEntry(type:String.self, forKey:curRelayHash, tx:subTrans)!
					buildStrings.update(with:getRelayString)
				}
				getRelays = buildStrings
			} catch LMDBError.notFound {
				let relays = Set(Topaz.defaultRelays.compactMap { $0.url })
				for curRelay in relays {
					let relayHash = try DBUX.RelayHash(curRelay)
					do {
						try self.relayHash_relayString.setEntry(value:curRelay, forKey:relayHash, flags:[], tx:subTrans)
					} catch LMDBError.keyExists {}
					do {
						try self.relayHash_pubKey.setEntry(value:publicKey, forKey:relayHash, flags:[.noDupData], tx:subTrans)
						try self.pubkey_relayHash.setEntry(value:relayHash, forKey:publicKey, flags:[.noDupData], tx:subTrans)
					} catch LMDBError.keyExists {}
				}
				getRelays = relays
			}
			var buildConnections = [String:RelayConnection]()
			var buildStates = [String:RelayConnection.State]()
			for curRelay in getRelays {
//				let relayHash = try DBUX.RelayHash(curRelay)
				let newConnection = RelayConnection(url:curRelay, stateChannel:stateC, eventChannel:eventC)
				buildConnections[curRelay] = newConnection
				buildStates[curRelay] = .disconnected
			}
			_userRelayConnections = Published(initialValue:buildConnections)
			_userRelayConnectionStates = Published(initialValue:buildStates)
			try subTrans.commit()
			try env.sync()
			self.digestTask = Task.detached { [weak self, sc = stateC, newEnv = env, logThing = newLogger, eventC = eventC] in
				await withThrowingTaskGroup(of:Void.self, body: { [weak self, sc = sc, newEnv = newEnv, ec = eventC] tg in
					// status
					tg.addTask { [weak self, sc = sc, newEnv = newEnv] in
						guard let self = self else { return }
						for await (curChanger, newState) in sc {
							let relayHash = try RelayHash(curChanger.url)
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
							case let .event(_/*subID*/, myEvent):
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
		func setRelays(_ relays:Set<String>, pubkey:nostr.Key, asOf writeDate:DBUX.Date) throws {
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
//			let relayStateCursor = try self.relayHash_relayState.cursor(tx:newTrans)

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
//								do {
//									try self.relayHash_relayConnection.deleteObject(type:RelayConnection.self, forKey:curRelayHash, tx:newTrans)
//								} catch LMDBError.notFound {}
								// - remove the public key associations
								try relayHashPubKeyCursor.deleteEntry()
								try relayHashCursor.deleteEntry()
								// - remove the actual URL string
								try relayStringCursor.deleteEntry()
								// - remove the state
//								try relayStateCursor.getEntry(.set, key:curRelayHash)
//								try relayStateCursor.deleteEntry()
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
//							do {
//								try self.relayHash_relayConnection.deleteObject(type:RelayConnection.self, forKey:curRelayHash, tx:newTrans)
//							} catch LMDBError.notFound {}
							// - remove the public key associations
							try relayHashPubKeyCursor.deleteEntry()
							try relayHashCursor.deleteEntry()
							// - remove the actual URL string
							try relayStringCursor.deleteEntry()
							// - remove the relay state
//							try relayStateCursor.getEntry(.set, key:curRelayHash)
//							try relayStateCursor.deleteEntry()
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
				let curRelayHash = try DBUX.RelayHash(curRelay)
				try relayHashCursor.setEntry(value:curRelayHash, forKey:pubkey)
				try relayHashPubKeyCursor.setEntry(value:pubkey, forKey:curRelayHash)
				try relayStringCursor.setEntry(value:curRelay, forKey:curRelayHash)
//				try relayStateCursor.setEntry(value:RelayConnection.State.disconnected, forKey:curRelayHash)
				try relaySubsCursor.setEntry(value:([] as [nostr.Subscription]), forKey:curRelayHash)
				try relayEventsCursor.setEntry(value:([] as [nostr.Event]), forKey:curRelayHash)
				if pubkey == self.pubkey {
					let newRelayConnection = RelayConnection(url:curRelay, stateChannel:stateChannel, eventChannel:eventChannel)
//					try self.relayHash_relayConnection.setObject(value:newRelayConnection, forKey:curRelayHash, tx:newTrans)
//					try relayStateCursor.setEntry(value:RelayConnection.State.disconnected, forKey:curRelayHash)
					buildStates[curRelay] = RelayConnection.State.disconnected
					buildConnections[curRelay] = newRelayConnection
				}
			}
			if assignRelays.count > 0 {
				didModify = true
			}

			// if these are the relays that belong to the current user, manage the current connections so that they can become an updated list of connections
			if pubkey == self.pubkey {
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
			if (didModify == true) {
				try env.sync()
			}
		}

		func add(subscriptions:[nostr.Subscribe], to relayURL:String) throws {
			let newTransaction = try Transaction(self.env, readOnly:false)
			let relayHash = try RelayHash(relayURL)
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
			Task.detached { @MainActor [weak self, rlurl = relayURL, subs = subscriptions] in
				guard let self = self else { return }
				guard let getConnectionState = self.userRelayConnectionStates[rlurl] else { return }
				guard case .connected = getConnectionState, let getConnection = self.userRelayConnections[rlurl] else { return }
				Task.detached { [conn = getConnection, subSubs = subs] in
					for curSub in subSubs {
						try await conn.send(.subscribe(curSub))
					}
				}
			}
			try newTransaction.commit()
			try env.sync()
		}
	}
}
