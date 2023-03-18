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
	class RelaysDB:ObservableObject {
		private static func produceRelayHash<B>(url:B) throws -> Data where B:ContiguousBytes {
			var newHasher = try Blake2bHasher(outputLength:8)
			try newHasher.update(url)
			return try newHasher.export()
		}
		
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

		enum Databases:String {
			case pubkey_relayHash = "pubkey-relayHash"
			case relayHash_relayString = "relayHash-relayString"
			case relayHash_pubKey = "relayHash-pubKey"
		}
		
		fileprivate let logger:Logger
		fileprivate let env:QuickLMDB.Environment
		let myPubkey:String

		private let pubkey_relayHash:Database		// stores the list of relay hashes that the user has listed in their profile	[String:String] * DUP *
		private let relayHash_relayString:Database	// stores the full relay URL for a given relay hash								[String:String]
		private let relayHash_pubKey:Database		// stores the public key for a given relay hash									[String:String] * DUP *

		@Published public private(set) var userRelayConnections:[String:RelayConnection]
		@Published public private(set) var userRelayConnectionStates:[String:RelayConnection.State]

		let holder:EventHolder
		private let eventChannel:AsyncChannel<RelayConnection.EventCapture>
		private let stateChannel:AsyncChannel<RelayConnection.StateChangeEvent>
		private var digestTask:Task<Void, Never>? = nil
		init(pubkey:String, env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
			self.env = env
			self.myPubkey = pubkey
			let newHolder = EventHolder(holdInterval:0.25)
			self.holder = newHolder
			
			let newLogger = Logger(label:"relay-db")
			let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
			let pubRelaysDB = try env.openDatabase(named:Databases.pubkey_relayHash.rawValue, flags:[.create, .dupSort], tx:subTrans)
			let relayStringDB = try env.openDatabase(named:Databases.relayHash_relayString.rawValue, flags:[.create], tx:subTrans)
			let pubRelaysCursor = try pubRelaysDB.cursor(tx:subTrans)
			let relayStringCursor = try relayStringDB.cursor(tx:subTrans)
			let eventC = AsyncChannel<RelayConnection.EventCapture>()
			let stateC = AsyncChannel<RelayConnection.StateChangeEvent>()
			self.eventChannel = eventC
			self.stateChannel = stateC
			self.pubkey_relayHash = pubRelaysDB
			self.relayHash_relayString = relayStringDB
			self.relayHash_pubKey = try env.openDatabase(named:Databases.relayHash_pubKey.rawValue, flags:[.create, .dupSort], tx:subTrans)
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
				let newConnection = RelayConnection(url:curRelay, stateChannel:stateC, eventChannel: eventC)
				buildConnections[curRelay] = newConnection
				buildStates[curRelay] = .disconnected
			}
			_userRelayConnections = Published(wrappedValue:buildConnections)
			_userRelayConnectionStates = Published(initialValue:buildStates)
			self.logger = newLogger
			try subTrans.commit()
			
			self.digestTask = Task.detached { [weak self, sc = stateC, ec = eventC, newEnv = env, logThing = newLogger, hol = holder] in
				await withThrowingTaskGroup(of:Void.self, body: { [weak self, sc = sc, ec = ec, newEnv = newEnv, hol = hol] tg in
					// status
					tg.addTask { [weak self, sc = sc, newEnv = newEnv] in
						guard let self = self else { return }
						for await (curChanger, newState) in sc {
							let newTrans = try Transaction(newEnv, readOnly:false)
							await self.relayConnectionStatusUpdated(relay:curChanger.url, state:newState)
							logThing.info("successfully updated relay connection state \(newState)")
							try newTrans.commit()
						}
					}
					// events intake into internal holder
					tg.addTask { [weak self, ec = ec, hol = hol] in
						guard let self = self else { return }
						for await (_, newEvent) in ec {
							
							logThing.info("an event was found in the relay stream")
						}
					}
				})
			}
		}
		
		// an internal function that an instance calls upon itself to update the relay connection state
		fileprivate func relayConnectionStatusUpdated(relay:String, state:RelayConnection.State) async {
			await MainActor.run(body: {
				self.userRelayConnectionStates[relay] = state
			})
		}

		// gets the relays for a given pubkey
		//  - throws LMDBError.notFound if the pubkey is not found
		func getRelays(pubkey:String, tx someTrans:QuickLMDB.Transaction) throws -> Set<String> {
			let newTrans = try Transaction(self.env, readOnly:true, parent:someTrans)
			var buildRelays = Set<String>()
			let relayHashCursor = try self.pubkey_relayHash.cursor(tx:newTrans)
			let relayStringCursor = try self.relayHash_relayString.cursor(tx:newTrans)
			for (_, curRelayHash) in try relayHashCursor.makeDupIterator(key:pubkey) {
				let relayString = try relayStringCursor.getEntry(.set, key:curRelayHash).value
				buildRelays.update(with:String(relayString)!)
			}
			return buildRelays
		}

		// sets the relays for a given pubkey
		//  - if the relay information is already in the database, it will be updated silently and any keys that existed previously will be dropped
		func setRelays(_ relays:Set<String>, pubkey:String, tx someTrans:QuickLMDB.Transaction) throws {
			let newTrans = try Transaction(self.env, readOnly:false, parent:someTrans)
			let relayHashCursor = try self.pubkey_relayHash.cursor(tx:newTrans)
			let relayStringCursor = try self.relayHash_relayString.cursor(tx:newTrans)
			let relayHashPubKeyCursor = try self.relayHash_pubKey.cursor(tx:newTrans)
			var assignRelays = relays
			do {
				// iterate through all existing entries and determine if they need to be removed from the database
				for (_ , curRelayHash) in try relayHashCursor.makeDupIterator(key:pubkey) {
					// check if the relay is still in the list of relays that we are setting
					let relayString = try relayStringCursor.getEntry(.set, key:curRelayHash).value
					if !assignRelays.contains(String(relayString)!) {
						// check if there are any other public keys that are using this relay
						do {
							try relayHashPubKeyCursor.getEntry(.getBoth, key:curRelayHash, value:pubkey)
							let relayHashPubKeyCount = try relayHashPubKeyCursor.dupCount()
							if relayHashPubKeyCount == 1 {
								// this is the only public key that is using this relay, so we can remove it from the database
								try relayHashPubKeyCursor.deleteEntry()
								try relayStringCursor.deleteEntry()
								try relayHashCursor.deleteEntry()
							} else {
								// there are other public keys that are using this relay, so we can just remove the public key from the list of public keys that are using this relay
								try relayHashPubKeyCursor.deleteEntry()
							}
						} catch LMDBError.notFound {
							// this should never happen, but if it does, we can just remove the relay from the database
							try relayHashPubKeyCursor.deleteEntry()
							try relayStringCursor.deleteEntry()
							try relayHashCursor.deleteEntry()
						}
					} else {
						// remove the relay from the list of relays that we are setting
						assignRelays.remove(String(relayString)!)
					}
				}
			} catch LMDBError.notFound {}

			// iterate through the list of relays that we are setting and add them to the database
			for curRelay in assignRelays {
				let curRelayHash = try RelaysDB.produceRelayHash(url:Data(curRelay.utf8))
				try relayHashCursor.setEntry(value:curRelayHash, forKey:pubkey)
				try relayStringCursor.setEntry(value:curRelay, forKey:curRelayHash)
				try relayHashPubKeyCursor.setEntry(value:pubkey, forKey:curRelayHash)
			}

			// if these are the relays that belong to the current user, manage the current connections so that they can become an updated list of connections
			if pubkey == myPubkey {
				let existingRelays = Set(self.userRelayConnections.keys)
				var editConnections = self.userRelayConnections
				let newRelays = relays
				let compare = Delta(start:existingRelays, end:newRelays)
				for curDrop in compare.exclusiveStart {
					if let hasItem = editConnections.removeValue(forKey:curDrop) {
						Task.detached { [item = hasItem] in
							try await item.forceClosure()
						}
					}
				}
				for curAdd in compare.exclusiveEnd {
					let newConn = RelayConnection(url:curAdd, stateChannel:stateChannel, eventChannel:eventChannel)
					editConnections[curAdd] = newConn
				}
				self.objectWillChange.send()
				self._userRelayConnections = Published(wrappedValue:editConnections)
			}
			try newTrans.commit()
		}
	}

}
