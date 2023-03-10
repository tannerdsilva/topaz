//
//  LNURLPayRequest.swift
//  topaz
//
//  Created by Tanner Silva on 3/10/23.
//

import Foundation

struct LNUrlPayRequest: Decodable {
	let allowsNostr: Bool?
	let commentAllowed: Int?
	let nostrPubkey: String?
	
	let metadata: String?
	let minSendable: Int64?
	let maxSendable: Int64?
	let status: String?
	let callback: String?
}



struct LNUrlPayResponse: Decodable {
	let pr: String
}
