//
//  Fetcher.swift
//  topaz
//
//  Created by Tanner Silva on 3/29/23.
//

import Foundation
import AsyncAlgorithms
import AsyncHTTPClient

class Fetcher: ObservableObject {
	static let logger = Topaz.makeDefaultLogger(label: "http-fetcher")

	enum State {
		case noData
		case loading
		case success(Data, String?)
		case failure(Swift.Error)
	}

	typealias InstanceStateChange = (Fetcher, State)

	@Published var state: State = .noData

	private let url:String
	private let stateChangeChannel:AsyncChannel<InstanceStateChange>
	private var runningTask:Task<Void, Swift.Error>? = nil

	init(_ url: String, channel: AsyncChannel<InstanceStateChange>) {
		self.stateChangeChannel = channel
		self.url = url
		let makeURL = URL(string: url)!
		runningTask = Task.detached { [weak self, makeURL] in
			guard let self = self else { return }
			do {
				await self.assignState(.loading)
				let (getData, getTC) = try await HTTP.get(url:makeURL)
				await self.assignState(.success(getData, getTC))
			} catch let error {
				await self.assignState(.failure(error))
			}
		}
	}

	private func assignState(_ state: State) async {
		let setState = Task.detached { @MainActor [weak self, stateIn = state] in
			guard let self = self else { return }
			self.state = stateIn
		}
		_ = await setState.result
		await stateChangeChannel.send((self, state))
	}
}
