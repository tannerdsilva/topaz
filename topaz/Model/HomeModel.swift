//
//  HomeModel.swift
//  topaz
//
//  Created by Tanner Silva on 3/13/23.
//

import Foundation

class HomeModel: ObservableObject {
	let dbux:DBUX


	init(_ dbux:DBUX) {
		self.dbux = dbux
	}
}
