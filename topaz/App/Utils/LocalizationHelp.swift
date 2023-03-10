//
//  LocalizationHelp.swift
//  topaz
//
//  Created by Tanner Silva on 3/9/23.
//

import Foundation

func bundleForLocale(locale: Locale?) -> Bundle {
	if locale == nil {
		return Bundle.main
	}

	let path = Bundle.main.path(forResource: locale!.identifier, ofType: "lproj")
	return path != nil ? (Bundle(path: path!) ?? Bundle.main) : Bundle.main
}
