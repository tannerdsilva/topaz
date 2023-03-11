////
////  RelayRegistrar.swift
////  topaz
////
////  Created by Tanner Silva on 3/11/23.
////
//
//import Foundation
//
//// allows users to register a subscription to a relay.
//actor RelayRegistrar {
//
//	// stores the connection for each relay url
//	private var url_relay = [String:RelayConnection]()
//
//	// stores the registration UID related to each relay connection
//	private var regristrar_relay = [String:RelayConnection]()
//	
//	
//	func subscribe(sub_id: String, filters: [nostr.Filter], handler: @escaping (String, NostrConnectionEvent) -> (), to: [String]? = nil) {
//		register_handler(sub_id: sub_id, handler: handler)
//		send(.subscribe(.init(filters: filters, sub_id: sub_id)), to: to)
//	}
//	
//	func subscribe_to(sub_id: String, filters: [NostrFilter], to: [String]?, handler: @escaping (String, NostrConnectionEvent) -> ()) {
//		register_handler(sub_id: sub_id, handler: handler)
//		send(.subscribe(.init(filters: filters, sub_id: sub_id)), to: to)
//	}
//	
//}
