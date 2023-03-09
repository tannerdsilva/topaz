//
//  Relay.swift
//  topaz
//
//  Created by Tanner Silva on 3/6/23.
//

struct Relay:Codable {
	let url:String
	
	init(_ url:String) {
		self.url = url
	}
}

extension Relay:Hashable {
	func hash(into hasher:inout Hasher) {
		hasher.combine(url)
	}
}

extension Relay:Equatable {
	static func == (lhs:Self, rhs:Self) -> Bool {
		return lhs.url == rhs.url
	}
}

extension Relay {
	struct PermissionLevel:OptionSet, RawRepresentable, Codable {
		init(rawValue:UInt8) {
			self.rawValue = rawValue
		}
		var rawValue: UInt8
		
		typealias RawValue = UInt8
		static let read:UInt8 = 1 << 0
		static let write:UInt8 = 1 << 1
	}
	struct Limitations:Codable {
		let payment_required:Bool?
	}
	struct Metadata:Codable {
		let relay:Relay
		let description:String?
		let pubkey:String?
		let contact:String?
		let supported_nips:[UInt]?
		let software:String?
		let version:String?
		let limitations:String?
		let payments_url:String?
		let permissions:PermissionLevel
	}
}
