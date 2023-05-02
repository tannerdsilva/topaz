//
//  Database.Statistics.swift
//  topaz
//
//  Created by Tanner Silva on 5/1/23.
//

import QuickLMDB

extension QuickLMDB.Database.Statistics {
	/// Calculates the amount of data utilized by the database.
	public var dataUtilized: UInt64 {
		// Calculate the total number of pages
		let totalPages: UInt64 = UInt64(branch_pages) + UInt64(leaf_pages) + UInt64(overflow_pages)
		
		// Calculate the total amount of data utilized
		let dataUtilized: UInt64 = totalPages * UInt64(pageSize)
		
		return dataUtilized
	}
}
