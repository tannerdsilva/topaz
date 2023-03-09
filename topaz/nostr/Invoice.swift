//
//  Invoice.swift
//  topaz
//
//  Created by Tanner Silva on 3/7/23.
//

import Foundation
typealias Invoice = LightningInvoice<Amount>

enum Amount:Equatable {
	case any
	case specific(Int64)

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

struct LightningInvoice<T> {
	enum Description {
		case string(String)
		case hash(Data)
	} 
	let description:Description
	let amount:T
	let string:String
	let expiry:Date
	let payment_hash:Data
	let created_on:Date
}
