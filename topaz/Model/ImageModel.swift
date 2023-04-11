//
//  ImageModel.swift
//  topaz
//
//  Created by Tanner Silva on 3/29/23.
//

import Foundation

class ImageModel {
	enum State {
		case noData
		case loading
		case success(Data, String?)
		case failure(Swift.Error)
	}

	let url:String
	
	@MainActor @Published var state: State

	init(_ url:String, state:State) {
		_state = Published(wrappedValue:state)
		self.url = url
	}

	private func setState(_ myState:State) {
		Task { @MainActor [weak self, myState] in
			guard let self = self else { return }
			self.state = myState
		}
	}

	func loadImage(_ whenComplete:@escaping (Result<(Data, String?), Swift.Error>) async -> Void) {
		Task { [weak self] in
			guard let self = self else { return }
			guard let parseURL = URL(string:self.url) else { return }
			do {
				let (data, contentType) = try await HTTP.getContent(url:parseURL)
				await whenComplete(.success((data, contentType)))
				self.setState(.success(data, contentType))
			} catch {
				await whenComplete(.failure(error))
				self.setState(.failure(error))
			}
		}
	}
}
