//
//  Invoice.swift
//  topaz
//
//  Created by Tanner Silva on 3/7/23.
//

import Foundation
typealias Invoice = LightningInvoice<Amount>
typealias ZapInvoice = LightningInvoice<Int64>

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
enum LightningInvoiceDescription {
	case string(String)
	case hash(Data)
}
struct LightningInvoice<T> {
	let description:LightningInvoiceDescription
	let amount:T
	let string:String
	let expiry:Date
	let payment_hash:Data
	let created_on:Date
}
