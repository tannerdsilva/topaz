//
//  RelativeDateDisplay.swift
//  topaz
//
//  Created by Tanner Silva on 5/1/23.
//

import Foundation
import SwiftUI

extension UI {
	class SharedTimer:ObservableObject {
		static let global = SharedTimer()
		private var interval: TimeInterval
		private var timerTask: Task<Void, Never>? = nil
		@MainActor @Published var now:DBUX.Date = DBUX.Date()
		
		private init(interval: TimeInterval = 1) {
			self.interval = interval
			self.startTimer()
		}
		
		func startTimer() {
			stopTimer()
			
			timerTask = Task.detached { @MainActor [weak self] in
				do {
					while Task.isCancelled == false {
						try await Task.sleep(nanoseconds:UInt64(size_t(1e+9)))
						self?.now = DBUX.Date()
					}
				} catch {}
			}
		}
		
		func stopTimer() {
			timerTask?.cancel()
			timerTask = nil
		}
		
		deinit {
			stopTimer()
		}
	}
}


// RelativeDateDisplay view
struct RelativeDateDisplay: View {
	@ObservedObject private var sharedTimer = UI.SharedTimer.global
	let date:DBUX.Date
	
	init(date:DBUX.Date) {
		self.date = date
		sharedTimer = sharedTimer
	}
	
	var body: some View {
		Text(date.relativeShortTimeString(to: sharedTimer.now)).foregroundColor(.secondary)

	}
}
