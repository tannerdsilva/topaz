//
//  HomeModel.swift
//  topaz
//
//  Created by Tanner Silva on 3/13/23.
//

import Foundation

class HomeModel: ObservableObject {
	let ue:UE

//	var

	init(_ ue:UE) {
		self.ue = ue
	}
}
