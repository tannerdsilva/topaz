//
//  HTTPTool.swift
//  topaz
//
//  Created by Tanner Silva on 3/25/23.
//

import NIO
import AsyncHTTPClient
import Logging
import Foundation

struct HTTP {
	enum Error: Swift.Error {
		case httpError(Swift.Error)
		case responseUnrecognized
	}

	static let logger = Topaz.makeDefaultLogger(label: "http-client")

	/// Invokes an HTTP GET request to the specified URL.
	/// - Returns a tuple containing the body content of the response, and the content type of the response, if available.
	/// - Throws an error if the request could not be completed
	static func getContent(url: URL) async throws -> (Data, String?) {
		let httpClient = HTTPClient(eventLoopGroupProvider: .shared(Topaz.defaultPool), configuration: HTTPClient.Configuration(timeout: HTTPClient.Configuration.Timeout(connect: .seconds(15), read: .seconds(30))))
		defer { try? httpClient.syncShutdown() }

		logger.trace("Requesting image.", metadata: ["url": "\(url)"])

		let request = try HTTPClient.Request(url: url, method: .GET)
		let response: HTTPClient.Response
		do {
			let deadline = NIODeadline.now() + .seconds(15)
			response = try await httpClient.execute(request: request, deadline: deadline).get()
		} catch let error {
			logger.error("There was an error retrieving image", metadata: ["url": "\(url)", "error": "\(error)"])
			throw Error.httpError(error)
		}

		guard response.status == .ok, var responseBody = response.body, let responseBytes = responseBody.readBytes(length: responseBody.readableBytes) else {
			logger.error("Unrecognized response while requesting image from URL: \(url)")
			throw Error.responseUnrecognized
		}
		
		let contentType = response.headers.first(name: "Content-Type")
		logger.info("Successfully retrieved image data from URL: \(url)")

		return (Data(responseBytes), contentType)
	}
}
