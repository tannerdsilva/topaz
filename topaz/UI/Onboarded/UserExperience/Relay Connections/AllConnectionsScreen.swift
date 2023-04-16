//
//  ConnectionDetailsView.swift
//  topaz
//
//  Created by Tanner Silva on 3/18/23.
//

import SwiftUI

extension UI.Relays {
	struct AllConnectionsScreen: View {
		@ObservedObject var relayDB: DBUX.RelaysEngine
		
		var sortedConnections: [(String, RelayConnection.State)] {
			relayDB.userRelayConnectionStates.sorted { lhs, rhs in
				switch (lhs.value, rhs.value) {
				case (.disconnected, .disconnected),
					(.connecting, .connecting),
					(.connected, .connected):
					return lhs.key < rhs.key
				case (.disconnected, _):
					return true
				case (.connecting, .connected):
					return true
				default:
					return false
				}
			}
		}
		
		var connectionGroups: [(RelayConnection.State, [(String, RelayConnection.State)])] {
			Dictionary(grouping: sortedConnections) { $0.1 }
				.map { ($0.key, $0.value) }
				.sorted { $0.0.rawValue < $1.0.rawValue }
		}
		
		var body: some View {
			NavigationView {
				VStack {
					List {
						ForEach(connectionGroups, id: \.0) { state, connections in
							Section(header: Text(state.description).font(.subheadline).foregroundColor(state.color).padding(.top)) {
								ForEach(connections, id: \.0) { key, value in
									HStack {
										VStack(alignment: .leading) {
											Text("\(key)")
												.font(.system(size: 14))
										}
										Spacer()
										
										// Add the reconnect button for disconnected relays
										if state == .disconnected {
											Button(action: {
												Task.detached { [relay = relayDB.userRelayConnections[key]!] in
													do {
														try await relay.connect(retryLaterIfFailed:true)
													} catch {
													}
												}
											}, label: {
												Text("Reconnect")
													.padding(.horizontal, 4)
													.padding(.vertical, 1)
													.background(.blue)
													.foregroundColor(.primary)
													.cornerRadius(4)
											})
										}
									}
									.padding(.vertical, 6)
								}
							}
						}
					}
					.listStyle(InsetGroupedListStyle())
				}
			}
		}
	}
}

extension RelayConnection.State {
	var description: String {
		switch self {
		case .disconnected:
			return "Disconnected"
		case .connecting:
			return "Connecting"
		case .connected:
			return "Connected"
		}
	}
	
	var color: Color {
		switch self {
		case .disconnected:
			return .red
		case .connecting:
			return .yellow
		case .connected:
			return .green
		}
	}
}
