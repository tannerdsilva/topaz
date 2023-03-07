//
//  UserEnvironment.swift
//  topaz
//
//  Created by Tanner Silva on 3/6/23.
//

import Foundation
import SwiftUI
import QuickLMDB

class UE:ObservableObject {

	let publicKey:String = ""
	let uuid:String = ""

	init(publicKey:String, uuid:String, env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction? = nil) throws {
		let subTrans = try Transaction(env, readOnly:false, parent:someTrans)

	}
}

extension UE:Hashable {
	func hash(into hasher: inout Hasher) {
		hasher.combine(uuid)
		hasher.combine(publicKey)
	}
}

extension UE:Equatable {
	static func == (lhs: UE, rhs: UE) -> Bool {
		return lhs.uuid == rhs.uuid && lhs.publicKey == rhs.publicKey
	}
}
