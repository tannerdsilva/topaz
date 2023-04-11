//
//  URL.swift
//  topaz
//
//  Created by Tanner Silva on 4/11/23.
//

import Foundation

extension URL {
	func getFileSize() -> off_t {
		var statObj = stat()
		guard stat(self.path, &statObj) == 0 else {
			return 0
		}
		return statObj.st_size
	}
}
