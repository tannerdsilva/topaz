//
//  Request.swift
//  topaz
//
//  Created by Tanner Silva on 3/7/23.
//

import Foundation


extension nostr {
	/// a subscription request to the server
	struct Subscribe:Codable {
		/// The subscription ID
		let sub_id:String
		/// The filters to apply to the subscription
		let filters:[Filter]
	}

	enum Subscription:Codable {
		enum Error:Swift.Error {
			case unknownRequestInstruction(String)
		}
		
		/// subscribe to a set of filters
		case subscribe(Subscribe)

		/// unsubscribe from a subscription ID
		case unsubscribe(String)

		/// send an event to the server
		case event(String, Event)
		
		/// the end of a stored event list
		case endOfStoredEvents(String)

		init(from decoder:Decoder) throws {
			var container = try decoder.unkeyedContainer()
			let type = try container.decode(String.self)
			switch type.uppercased() {
				case "REQ":
					let sub_id = try container.decode(String.self)
					var filters = [Filter]()
					while container.isAtEnd == false {
						filters.append(try container.decode(Filter.self))
					}
					self = .subscribe(Subscribe(sub_id: sub_id, filters:filters))
				case "CLOSE":
					let sub_id = try container.decode(String.self)
					self = .unsubscribe(sub_id)
				case "EVENT":
					let subID = try container.decode(String.self)
					let event = try container.decode(Event.self)
					self = .event(subID, event)
				case "EOSE":
					let subID = try container.decode(String.self)
					self = .endOfStoredEvents(subID)
			default:
				throw Error.unknownRequestInstruction(type)
			}
		}

		func encode(to encoder:Encoder) throws {
			var container = encoder.unkeyedContainer()
			switch self {
				case .subscribe(let sub):
					try container.encode("REQ")
					try container.encode(sub.sub_id)
					for cur_filter in sub.filters {
						try container.encode(cur_filter)
					}
				case .unsubscribe(let sub_id):
					try container.encode("CLOSE")
					try container.encode(sub_id)
				case .event(_, let event):
					try container.encode("EVENT")
					try container.encode(event)
				case .endOfStoredEvents(let subID):
					try container.encode("EOSE")
					try container.encode(subID)
			}
		}
	}
}
