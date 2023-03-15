////
////  RelayRegistrar.swift
////  topaz
////
////  Created by Tanner Silva on 3/11/23.
////

import Foundation
import QuickLMDB
import AsyncAlgorithms


// allows users to register a subscription to a relay.
actor RelayRegistrar {

	// stores the connection for each relay url
	private var url_relay = [String:RelayConnection]()

	// stores the registrars for each relay url
	private var url_registrars = [String:Set<String>]()
	// stores the relay url that each registrar is associated with
	private var registrar_url = [String:String]()
	// messages that are waiting to be sent to 
	private var url_pending = [String:[nostr.Filter]]()

	let env:QuickLMDB.Environment
	
	let mainChannel:AsyncChannel<RelayConnection.Event>
	
	init(_ env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
		self.env = env
		self.mainChannel = AsyncChannel<RelayConnection.Event>()
	}
	
	fileprivate func handleEvent() {
		// handle event here
	}
	
	// subscribes a given set of subscriber ID's (with a given set of filters) to a given set of relay urls
	func subscribe(_ subs_filters:[String:[nostr.Filter]], to relay_urls:[String]) throws {
		// for each relay url
		for relay_url in relay_urls {
			// if the relay url is not already registered
			if url_relay[relay_url] == nil {
				// create a new relay connection
				let relay = RelayConnection(url:relay_url, channel:mainChannel)
				// store the relay connection
				url_relay[relay_url] = relay
				// store the pending messages
				url_pending[relay_url] = []
			}
			// for each subscriber ID
			for (sub_id, filters) in subs_filters {
				// if the subscriber ID is not already registered (do not override existing registrations)
				if registrar_url[sub_id] == nil {
					// store the subscriber ID
					registrar_url[sub_id] = relay_url
					// store the relay url
					url_registrars[relay_url, default: []].insert(sub_id)
				}
				// store the pending messages
				url_pending[relay_url]!.append(contentsOf: filters)
			}
		}
		// for each relay url
		for relay_url in relay_urls {
			// if there are pending messages
			if let pending = url_pending[relay_url] {
				// send the pending messages
//				url_relay[relay_url]!.send(.subscribe(.init(filters: pending, sub_id: "registrar")), to: Array(url_registrars[relay_url]!))
				// clear the pending messages
				url_pending[relay_url] = nil
			}
		}
	}

//	func subscribe(sub_id: String, filters: [nostr.Filter], handler: @escaping (String, NostrConnectionEvent) -> (), to: [String]? = nil) {
//		register_handler(sub_id: sub_id, handler: handler)
//		send(.subscribe(.init(filters: filters, sub_id: sub_id)), to: to)
//	}
//
//	func subscribe_to(sub_id: String, filters: [NostrFilter], to: [String]?, handler: @escaping (String, NostrConnectionEvent) -> ()) {
//		register_handler(sub_id: sub_id, handler: handler)
//		send(.subscribe(.init(filters: filters, sub_id: sub_id)), to: to)
//	}
	
}
