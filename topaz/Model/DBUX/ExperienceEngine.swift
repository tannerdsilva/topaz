//
//  UserExperience.swift
//  topaz
//
//  Created by Tanner Silva on 4/11/23.
//

import class QuickLMDB.Environment
import struct Foundation.URL

protocol Based {
	var base:URL { get }
}
protocol ExperienceEngine:Based {
	var base:URL { get }
	var env:QuickLMDB.Environment { get }
	init(base:URL, pubkey:String) throws
}
