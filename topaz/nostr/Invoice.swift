//
//  Invoice.swift
//  topaz
//
//  Created by Tanner Silva on 3/7/23.
//

import Foundation
typealias Invoice = LightningInvoice<Amount>
typealias ZapInvoice = LightningInvoice<Int64>

enum Amount:Equatable, Hashable, Codable {
	enum Error:Swift.Error {
		case unknownType(UInt8)
	}
	case any
	case specific(Int64)

	// for the codable protocol
	init(from decoder: Decoder) throws {
		var container = try decoder.unkeyedContainer()
		let type = try container.decode(UInt8.self)
		switch type {
		case 0:
			self = .any
		case 1:
			let val = try container.decode(Int64.self)
			self = .specific(val)
		default:
			throw Error.unknownType(type)
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.unkeyedContainer()
		switch self {
		case .any:
			try container.encode(UInt8(0))
		case .specific(let val):
			try container.encode(UInt8(1))
			try container.encode(val)
		}
	}

	// for the hashable protocol
	 func hash(into hasher: inout Hasher) {
		switch self {
		case .any:
			hasher.combine("\nANY\n")
		case .specific(let val):
			hasher.combine(val)
		}
	}
	// for the equatable protocol
	static func == (lhs:Amount, rhs:Amount) -> Bool {
		switch (lhs, rhs) {
		case (.any, .any):
			return true
		case let (.specific(l), .specific(r)):
			return l == r
		default:
			return false
		}
	}
}

enum LightningInvoiceDescription:Hashable, Equatable, Codable {
	enum Error:Swift.Error {
		case unknownType(UInt8)
	}

	case string(String)
	case hash(Data)
	
	// for the codable protocol
	init(from decoder: Decoder) throws {
		var container = try decoder.unkeyedContainer()
		let type = try container.decode(UInt8.self)
		switch type {
		case 0:
			let str = try container.decode(String.self)
			self = .string(str)
		case 1:
			let hash = try container.decode(Data.self)
			self = .hash(hash)
		default:
			throw Error.unknownType(type)
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.unkeyedContainer()
		switch self {
		case .string(let strVal):
			try container.encode(UInt8(0))
			try container.encode(strVal)
		case .hash(let hashVal):
			try container.encode(UInt8(1))
			try container.encode(hashVal)
		}
	}

	// for the hashable protocol
	func hash(into hasher: inout Hasher) {
		switch self {
		case .string(let strVal):
			hasher.combine(strVal)
		case .hash(let hashVal):
			hasher.combine(hashVal)
		}
	}
	
	// for the equatable protocol
	static func == (lhs:LightningInvoiceDescription, rhs:LightningInvoiceDescription) -> Bool {
		switch (lhs, rhs) {
			case let (.string(l), .string(r)):
				return l == r
			case let (.hash(l), .hash(r)):
				return l == r
			default:
				return false
		}
	}
}
struct LightningInvoice<T>:Codable where T:Equatable & Hashable & Codable {
	let description:LightningInvoiceDescription
	let amount:T
	let string:String
	let expiry:Date
	let payment_hash:Data
	let created_on:UInt64
}
