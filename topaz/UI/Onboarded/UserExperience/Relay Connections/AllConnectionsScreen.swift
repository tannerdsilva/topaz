//
//  ConnectionDetailsView.swift
//  topaz
//
//  Created by Tanner Silva on 3/18/23.
//

import SwiftUI

extension UI.Relays {
	struct AllConnectionsScreen: View {
		struct ConnectionListItem: View {
			let url: String
			let state: RelayConnection.State
			let showReconnectButton: Bool
			
			var body: some View {
				HStack {
					RelayProtocolView(url: url)
						.padding(.trailing, 8)

					VStack(alignment: .leading) {
						Text("\(url.replacingOccurrences(of: "ws://", with: "").replacingOccurrences(of: "wss://", with: ""))")
							.font(.system(size: 14))
					}
					Spacer()
					
					if showReconnectButton && state == .disconnected {
						Button(action: {
							// Reconnect action
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

		struct CustomToolbar: View {
			let isEditMode: EditMode
			let onEditToggle: () -> Void

			var body: some View {
				HStack {
					Spacer()
					if isEditMode == .active {
						Button(action: {
							onEditToggle()
						}) {
							Text("Done")
								.foregroundColor(.blue)
								.padding(.horizontal, 16)
								.padding(.vertical, 8)
								.background(Color(.systemBackground))
								.cornerRadius(8)
								.overlay(
									RoundedRectangle(cornerRadius: 8)
										.stroke(Color(.systemBlue), lineWidth: 1)
								)
						}
					} else {
						Button(action: {
							onEditToggle()
						}) {
							Text("Edit")
								.foregroundColor(.blue)
								.padding(.horizontal, 16)
								.padding(.vertical, 8)
								.background(Color(.systemBackground))
								.cornerRadius(8)
								.overlay(
									RoundedRectangle(cornerRadius: 8)
										.stroke(Color(.systemBlue), lineWidth: 1)
								)
						}
					}
					Spacer()
				}
				.padding(.top, 8)
			}
		}

		@ObservedObject var relayDB: DBUX.RelaysEngine
		
		@State private var isEditMode: EditMode = .inactive
		@State private var newRelayURL: String = ""
		
		var sortedConnections: [(String, RelayConnection.State)] {
			relayDB.userRelayConnectionStates.sorted { lhs, rhs in
				lhs.key < rhs.key
			}
		}
		
		var connectionGroups: [(RelayConnection.State, [(String, RelayConnection.State)])] {
			Dictionary(grouping: sortedConnections) { $0.1 }
				.map { ($0.key, $0.value) }
				.sorted { $0.0.rawValue < $1.0.rawValue }
		}
		
		func deleteConnection(at offsets: IndexSet) {
			var updatedURLs = Set<String>()

			for (index, connection) in sortedConnections.enumerated() {
				if !offsets.contains(index) {
					updatedURLs.insert(connection.0)
				}
			}

			do {
				// Replace "pubkey" and "writeDate" with the appropriate values from your app
				try relayDB.setRelays(updatedURLs, pubkey:relayDB.pubkey, asOf: DBUX.Date())
			} catch {
				// Handle the error if needed, e.g., show an alert or print a message
				print("Error updating relays: \(error)")
			}
		}

		
		var body: some View {
			NavigationView {
				VStack {
					CustomToolbar(isEditMode: isEditMode) {
						isEditMode = isEditMode == .active ? .inactive : .active
					}
					
					if isEditMode == .active {
						Section(header: Text("Add New Relay").font(.subheadline)) {
							HStack {
								TextField("Enter Relay URL", text: $newRelayURL)
									.textFieldStyle(RoundedBorderTextFieldStyle())
								Button(action: {
									// Add new relay logic here
								}) {
									Text("Add")
										.foregroundColor(.blue)
								}
							}
						}
					}
					
					List {
						// Add a section for adding a new relay
						
						if isEditMode == .inactive {
							ForEach(connectionGroups, id: \.0) { state, connections in
								Section(header: Text(state.description).font(.subheadline).foregroundColor(state.color).padding(.top)) {
									ForEach(connections, id: \.0) { key, value in
										ConnectionListItem(url: key, state: value, showReconnectButton: true)
									}
								}
							}
						} else {
							ForEach(sortedConnections, id: \.0) { key, state in
								ConnectionListItem(url: key, state: state, showReconnectButton: false)
							}
						}
					}
					.listStyle(InsetGroupedListStyle())
					.environment(\.editMode, $isEditMode)
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
