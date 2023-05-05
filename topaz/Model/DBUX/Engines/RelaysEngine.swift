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
	class RelaysEngine:ObservableObject, SharedExperienceEngine {
		typealias NotificationType = DBUX.Notification
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let dispatcher: Dispatcher<DBUX.Notification>
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

		let holder:Holder<(String, nostr.Event)>

		// stores the relay connections for the current user
		@MainActor @Published public private(set) var userRelayConnections = [String:RelayConnection]()
		// stores the relay connection states for the current user
		@MainActor @Published public private(set) var userRelayConnectionStates = [String:RelayConnection.State]()
		@MainActor public func getConnectionsAndStates() -> ([String:RelayConnection], [String:RelayConnection.State]) {
			return (self.userRelayConnections, self.userRelayConnectionStates)
		}
		@MainActor @Published public private(set) var relaySyncStates = [String:[String:Bool]]()
		
		private let eventChannel:AsyncChannel<RelayConnection.EventCapture>
		private let stateChannel:AsyncChannel<RelayConnection.StateChangeEvent>
		private let subscriptionsChannel:AsyncChannel<RelayConnection.SubscriptionChangeEvent>
		
		private var digestTask:Task<Void, Never>? = nil
		
		let pubkey_relays_asof:Database
		let pubkey_relayHash:Database
		let relayHash_pubKey:Database
		let relayHash_relayString:Database
		
		let relayHash_pendingEvents:Database
		let relayHash_currentSubscriptions:Database
		
		required init(env: QuickLMDB.Environment, publicKey: nostr.Key, dispatcher: Dispatcher<DBUX.Notification>) throws {
			self.dispatcher = dispatcher
			self.env = env
			self.holder = Holder<(String, nostr.Event)>(holdInterval:0.35)
			var newLogger = Topaz.makeDefaultLogger(label:"relay-engine.mdb")
			newLogger.logLevel = .trace
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
			let subC = AsyncChannel<RelayConnection.SubscriptionChangeEvent>()
			self.eventChannel = eventC
			self.stateChannel = stateC
			self.subscriptionsChannel = subC
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
				let newConnection = RelayConnection(url:curRelay, stateChannel:stateC, eventChannel:eventC, subscriptionChannel: subC)
				buildConnections[curRelay] = newConnection
				buildStates[curRelay] = .disconnected
			}
			_userRelayConnections = Published(wrappedValue:buildConnections)
			_userRelayConnectionStates = Published(wrappedValue:buildStates)
			try subTrans.commit()
			try env.sync()
			
			self.digestTask = Task.detached { [weak self, sc = stateC, newEnv = env, logThing = newLogger, eventC = eventC, pk = self.pubkey, rhCS = self.relayHash_currentSubscriptions, holder = self.holder, subC = subC] in
				await withThrowingTaskGroup(of:Void.self, body: { [weak self, sc = sc, newEnv = newEnv, ec = eventC, holder = holder, subc = subC] tg in
					// status
					tg.addTask { [weak self, sc = sc, newEnv = newEnv] in
						try await withTaskCancellationHandler(operation: {
							for await (curChanger, newState) in sc {
	//							guard let self = self else { return }
								let relayHash = try RelayHash(curChanger.url)
								let newTrans = try Transaction(newEnv, readOnly:false)
								if case .connected = newState {
									// need to send all subscriptions to relay
									do {
										var ourContactsFilter = nostr.Filter()
										ourContactsFilter.kinds = [.metadata, .contacts]
										ourContactsFilter.authors = [pk]

										let makeSub = nostr.Subscribe.init(sub_id:"-ux-self-", filters: [ourContactsFilter])
										try await curChanger.send(.subscribe(makeSub))
										if let getSubs = try rhCS.getEntry(type:[nostr.Subscribe].self, forKey:relayHash, tx:newTrans) {
											for curSub in getSubs {
												do {
													try await curChanger.send(.subscribe(curSub))
												} catch let error {
													logThing.critical("there was a problem writing the message to the relay", metadata:["error":"\(error)"])
												}
											}
										}
									} catch {}
								}
								self?.relayConnectionStatusUpdated(relay:curChanger.url, state:newState)
								logThing.trace("successfully updated relay connection state \(newState)", metadata:["url":"\(curChanger.url)"])
								try newTrans.commit()
							}
						}, onCancel: {
							sc.finish()
						})
					}

					// events
					tg.addTask { [hol = holder, ec = ec] in
						await withTaskCancellationHandler(operation: {
							for await curEvent in ec {
								switch curEvent.1 {
								case let .event(subID, myEvent):
									logThing.trace("got event.", metadata:["kind":"\(myEvent.kind.rawValue)", "pubkey":"\(myEvent.pubkey)"])
									await hol.append(element: (subID, myEvent))
									break;
								case .endOfStoredEvents(let subID):
									logThing.trace("end of events", metadata:["sub_id":"\(subID)"])
									break;
								default:
									break;
								}
							}
						}, onCancel: {
							ec.finish()
						})
					}
					
					// sync info
					tg.addTask { [weak self, sc = subc] in
						await withTaskCancellationHandler(operation: {
							for await curEvent in sc {
								logThing.info("relay info updated: '\(curEvent.0.url)'.", metadata:["all":"\(curEvent.1.count)", "eose":"\(curEvent.2.count)"])
								var buildEvent = [String:Bool]()
								for curSub in curEvent.1 {
									if curEvent.2.contains(curSub) {
										buildEvent[curSub] = true
									} else {
										buildEvent[curSub] = false
									}
								}
								Task.detached { @MainActor [weak self, url = curEvent.0.url, be = buildEvent] in
									await self?.relaySyncStates[url] = be
								}
								
							}
						}, onCancel: {
							sc.finish()
						})
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
		
		@MainActor func write(event:nostr.Event, to relays:Set<String>, tx someTrans:QuickLMDB.Transaction) throws {
			for relay in relays {
				let makeRelayHash = try RelayHash(relay)
				var existingEvents:[nostr.Event]
				do {
					existingEvents = try self.relayHash_pendingEvents.getEntry(type:[nostr.Event].self, forKey:makeRelayHash, tx:someTrans)!
				} catch LMDBError.notFound {
					existingEvents = [nostr.Event]()
				}
				existingEvents.append(event)
				try self.relayHash_pendingEvents.setEntry(value:existingEvents, forKey:makeRelayHash, tx:someTrans)
			}
			Task.detached { [relaysCopy = relays, event, conns = self.userRelayConnections] in
				for curRelay in relaysCopy {
					if let getConnection = conns[curRelay] {
						try? await getConnection.send(event)
					}
				}
			}
		}
		
		// gets the relays for a given pubkey
		//  - throws LMDBError.notFound if the pubkey is not found
		func getRelays(pubkey:nostr.Key, tx someTrans:QuickLMDB.Transaction) throws -> Set<String> {
			var buildRelays = Set<String>()
			let relayHashCursor = try self.pubkey_relayHash.cursor(tx:someTrans)
			let relayStringCursor = try self.relayHash_relayString.cursor(tx:someTrans)
			for (_, curRelayHash) in try relayHashCursor.makeDupIterator(key:pubkey) {
				let relayString = try relayStringCursor.getEntry(.set, key:curRelayHash).value
				buildRelays.update(with:String(relayString)!)
			}
			return buildRelays
		}

		func setRelays(_ relays:Set<String>, pubkey:nostr.Key, asOf writeDate:DBUX.Date, tx someTrans:QuickLMDB.Transaction) throws {
			#if DEBUG
			self.logger.critical("attempting to assign \(relays.count) relays for pubkey \(pubkey) as of \(writeDate.exportDate())")
			#endif
			let newTrans = try Transaction(self.env, readOnly:false, parent:someTrans)
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

			// replace the paired databases that store the relationship between a member and their relays
			let pubkey_relayHashC = try self.pubkey_relayHash.cursor(tx:newTrans)
			let relayHash_pubkeyC = try self.relayHash_pubKey.cursor(tx:newTrans)
			let relayStringC = try self.relayHash_relayString.cursor(tx:newTrans)
			
			// delete all entries for this pubkey
			for (_, curHash) in try pubkey_relayHashC.makeDupIterator(key:pubkey) {
				try relayHash_pubkeyC.getEntry(.set, key:curHash)
				try relayHash_pubkeyC.deleteEntry()
				try pubkey_relayHashC.deleteEntry()
			}
			
			// write all the new relays
			for curRelay in relays {
				let relayHash = try RelayHash(curRelay)
				try relayStringC.setEntry(value:curRelay, forKey:relayHash)
				try relayHash_pubkeyC.setEntry(value:pubkey, forKey:relayHash)
				try pubkey_relayHashC.setEntry(value:relayHash, forKey:pubkey)
			}
			
			try newTrans.commit()
			Task.detached { @MainActor [weak self, newConnections = relays] in
				guard let self = self else { return }
				let existingConnections = Set(self.userRelayConnections.keys)
				let connectionsDelta = Delta(start:existingConnections, end:newConnections)
				for curRelay in connectionsDelta.exclusiveEnd {
					self.userRelayConnections[curRelay] = RelayConnection(url:curRelay, stateChannel:self.stateChannel, eventChannel:self.eventChannel, subscriptionChannel:self.subscriptionsChannel)
					self.userRelayConnectionStates[curRelay] = RelayConnection.State.disconnected
				}
				for curRelay in connectionsDelta.exclusiveStart {
					self.userRelayConnections.removeValue(forKey:curRelay)
					self.userRelayConnectionStates.removeValue(forKey: curRelay)
				}
			}
		}

		func addOrUpdate(subscriptions:[nostr.Subscribe], to relayURL:String, tx subTrans:QuickLMDB.Transaction) throws {
			let newTransaction = try Transaction(self.env, readOnly:false, parent:subTrans)
			let relayHash = try RelayHash(relayURL)
			let relaySubscriptionsCursor = try self.relayHash_currentSubscriptions.cursor(tx:newTransaction)
			// the modified subs that need to be written
			var updateSubs = Set<nostr.Subscribe>()
			// load the existing subscriptions
			var currentSubscriptions:[String:nostr.Subscribe]
			do {
				currentSubscriptions = Dictionary<String, nostr.Subscribe>(try relaySubscriptionsCursor.getEntry(.set, key:relayHash).value)!
			} catch _ {
				currentSubscriptions = [:]
			}
			for curSub in subscriptions {
				if let hasExistingSub = currentSubscriptions[curSub.sub_id] {
					if hasExistingSub == curSub {
						updateSubs.update(with:curSub)
					}
				}
				currentSubscriptions[curSub.sub_id] = curSub
			}
			try relaySubscriptionsCursor.setEntry(value:currentSubscriptions, forKey:relayHash)
			
			// check if this relay is connected, and if it is, send the subscriptions to the relay
			Task.detached { @MainActor [weak self, rlurl = relayURL, subs = updateSubs] in
				guard let self = self else { return }
				guard let getConnectionState = self.userRelayConnectionStates[rlurl] else { return }
				guard case .connected = getConnectionState, let getConnection = self.userRelayConnections[rlurl] else { return }
				Task.detached { [conn = getConnection, subSubs = subs] in
					for curSub in subSubs {
						try? await conn.send(.subscribe(curSub))
					}
				}
			}
			try newTransaction.commit()
		}
		
		deinit {
			self.digestTask?.cancel()
		}
	}
}
