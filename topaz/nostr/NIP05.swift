//
//  NIP05.swift
//  topaz
//
//  Created by Tanner Silva on 3/9/23.
//

import Foundation
import AsyncHTTPClient

struct NIP05 {
	static internal let logger = Topaz.makeDefaultLogger(label:"nip-05")

	enum Error:Swift.Error {
		case invalidURL
		case invalidResponse
	}
	struct Response:Codable {
		let names:[String:String]
		let relays:[String:String]
	}
	let username:String
	let host:String
	
	static func parse(_ nip05:String) -> NIP05? {
		let parts = nip05.split(separator:"@")
		guard parts.count == 2 else {
			return nil
		}
		return NIP05(username:String(parts[0]), host:String(parts[1]))
	}

	static func retrieveVerificationInfo(url:String, name:String) async throws -> Response {
		let newClient = HTTPClient(eventLoopGroupProvider: .createNew)
		defer {
			try? newClient.syncShutdown()
		}
		// validate that the URL looks halfway sane
		guard let baseURL = URL(string:url) else {
			throw Error.invalidURL
		}
		// build URL components out of the base url
		var components = URLComponents()
		components.scheme = baseURL.scheme
		components.host = baseURL.host
		components.path = baseURL.path
		// add the query items
		var queryItems = [URLQueryItem]()
		queryItems.append(URLQueryItem(name:"name", value:name))
		components.queryItems = queryItems
		// build the request
		guard let requestURL = components.url else {
			Self.logger.error("unable to execute NIP-05 request. an invalid url was provided.", metadata:["url":"\(url)"])
			throw Error.invalidURL
		}
		let request = try HTTPClient.Request(url:requestURL, method:.GET)
		// send the request
		let response = try await newClient.execute(request: request).get()
		guard response.status == .ok, var responseBody = response.body, let responseBytesRead = responseBody.readBytes(length:responseBody.readableBytes) else {
			throw Error.invalidResponse
		}
		// decode the response
		let decoder = JSONDecoder()
		let decodedResponse = try decoder.decode(Response.self, from:Data(responseBytesRead))
		return decodedResponse
	}
}
