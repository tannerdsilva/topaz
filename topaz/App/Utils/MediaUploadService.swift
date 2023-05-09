//
//  MediaUploadService.swift
//  topaz
//
//  Created by Tanner Silva on 5/6/23.
//

import Foundation
import AsyncHTTPClient
import NIO

enum MediaUpload {
	class Model:ObservableObject, HTTPClientResponseDelegate {
		func didFinishRequest(task: AsyncHTTPClient.HTTPClient.Task<Void>) throws -> Void {
			return
		}
		func didSendRequestPart(task: HTTPClient.Task<Response>, _ newPart: IOData) {
			Task.detached { @MainActor [weak self, np = newPart.readableBytes] in
				guard let self = self else { return }
				switch self.status {
				case let .uploading(part, whole):
					self.status = .uploading(part + UInt64(np), whole)
				default:
					break;
				}
			}
			
		}
		typealias Response = Void
		
		enum Error:Swift.Error {
			case invalidState
			case unrecognizedResponse
		}
		enum Status {
			case idle
			case uploading(UInt64, UInt64)
			case complete(Result<String, Swift.Error>)
		}
		private let logger = Topaz.makeDefaultLogger(label: "media-upload-model")
		private let httpClient =  HTTPClient(eventLoopGroupProvider:.shared(Topaz.defaultPool), configuration:HTTPClient.Configuration(timeout:HTTPClient.Configuration.Timeout(connect:.seconds(7), read:.seconds(45))))
		@MainActor @Published var status:Status = .idle
		let postData:Data
		var uploadTask:Task<Void, Swift.Error>? = nil
		init(postData:Data) {
			self.postData = postData
		}
		
		@MainActor func begin() throws {
			guard case .idle = self.status else {
				return
			}
			
			self.status = .uploading(0, UInt64(postData.count))
			
			self.uploadTask = Task.detached { [cli = httpClient, logger = self.logger, cont = self.postData] in
				let boundary = "Boundary-\(UUID().description)"
				// build the HTTP body package
				var buildData = Data()
				buildData.append(Data("Content-Type: multipart/form-data; boundary=\(boundary)\r\n\r\n".utf8))
				buildData.append(Data("--\(boundary)\r\n".utf8))
				buildData.append(Data("Content-Disposition: form-data; name=\"fileToUpload\"; filename=topaz_generic_filename.jpg\r\n".utf8))
				buildData.append(Data("Content-Type: image/jpg\r\n\r\n".utf8))
				buildData.append(cont)
				buildData.append(Data("\r\n--\(boundary)--\r\n".utf8))
				var asByteBuffer = ByteBuffer()
				asByteBuffer.writeData(buildData)
				let buildRequest = try HTTPClient.Request(url:"https://nostr.build/api/upload/ios.php", method:.POST, headers:["Content-Type":"multipart/form-data; boundary=\(boundary)"], body: .byteBuffer(asByteBuffer))
				let deadline = NIODeadline.now() + .seconds(15)
				guard Task.isCancelled == false else {
					return
				}
				let response = try await cli.execute(request:buildRequest, deadline:deadline).get()
				guard response.status == .ok, var responseBody = response.body, let responseBytes = responseBody.readBytes(length:responseBody.readableBytes) else {
					logger.error("unexpected response from server.", metadata:["status":"\(response.status)"])
					throw Error.unrecognizedResponse
				}
				guard let asString = String(data:Data(responseBytes), encoding:.utf8) else {
					logger.error("failed to upload to server.")
					throw Error.unrecognizedResponse
				}
				guard Task.isCancelled == false else {
					return
				}
				Task.detached { @MainActor [weak self, asstr = asString] in
					self?.status = .complete(.success(asstr))
				}
			}
		}
		
		deinit {
			do {
				try httpClient.syncShutdown()
			} catch let error {
				self.logger.error("failed to safely shutdown http client with .syncShutdown().", metadata:["error":"\(error)"])
			}
		}
	}
	
	case image(URL)
	
	var file_extension:String {
		switch self {
		case.image(let url):
			return url.pathExtension
		}
	}
	
	var localURL:URL {
		switch self {
		case .image(let url):
			return url
		}
	}
}

enum MediaUploadServices {
	case nostrBuild
	
	var postAPI:String {
		switch self {
		case .nostrBuild:
			return "https://nostr.build/api/upload/ios.php"
		}
	}
}

