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
			let dbux: DBUX
			let url: String
			let state: RelayConnection.State
			let showReconnectButton: Bool
			@Binding var editMode: EditMode
			@State private var inputURL: String = "" // Add a State property to store the input URL
			
			private var isValidURL: Bool {
				if let url = URL(string: inputURL), url.scheme == "ws" || url.scheme == "wss" {
					return true
				} else {
					return false
				}
			}
			
			var body: some View {
				HStack {
					RelayProtocolView(url: URL(string: url)) // Update to use URL struct
						.padding(.trailing, 8)
					
					VStack(alignment: .leading) {
						Text("\(url.replacingOccurrences(of: "ws://", with: "").replacingOccurrences(of: "wss://", with: ""))")
							.font(.system(size: 14, design: .monospaced)) // Use a monospaced font
					}
					Spacer()
					
					if showReconnectButton && state == .disconnected {
						Button(action: {
							Task.detached {
								try await dbux.eventsEngine.relaysEngine.userRelayConnections[url]!.connect()
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
					
					if editMode == .active {
						Button(action: {
							try? dbux.removeRelay(url)
						}) {
							Image(systemName: "trash")
								.foregroundColor(.red)
						}
						.contentShape(Rectangle()) // Make only the button's area tappable
					}
				}
				.padding(.vertical, 6)
				.onChange(of: inputURL) { newValue in
					if isValidURL {
						try? dbux.addRelay(newValue)
						inputURL = ""
					}
				}
			}
		}
		
		struct CustomToolbar: View {
			let isEditMode: EditMode
			let onEditToggle: () -> Void
			
			var body: some View {
				HStack {
					Spacer()
					if isEditMode == .active {
						actionButton(title: "Done", action: onEditToggle)
					} else {
						actionButton(title: "Edit", action: onEditToggle)
					}
					Spacer()
				}
				.padding(.top, 8)
			}
			
			func actionButton(title: String, action: @escaping () -> Void) -> some View {
				Button(action: action) {
					Text(title)
						.font(.system(size: 14))
						.foregroundColor(.white)
						.padding(.horizontal, 12)
						.padding(.vertical, 6)
						.background(Color.blue)
						.cornerRadius(4)
				}
			}
		}
		
		let dbux:DBUX
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

		var body: some View {
			NavigationView {
				VStack {
					CustomToolbar(isEditMode: isEditMode) {
						isEditMode = isEditMode == .active ? .inactive : .active
					}
					
					if isEditMode == .active {
						HStack {
							TextField("wss://relay.url.here", text: $newRelayURL)
								.textFieldStyle(RoundedBorderTextFieldStyle())
								.font(.system(size: 15, design: .monospaced))
								.disableAutocorrection(true)
								.autocapitalization(.none)
								.padding(.horizontal, 3)
							Button(action: {
								try? dbux.addRelay(newRelayURL)
							}) {
								Text("Add")
									.foregroundColor(.blue)
							}
						}.padding(.horizontal, 20)
					}

					
					List {
						if isEditMode == .inactive {
							ForEach(connectionGroups, id: \.0) { state, connections in
								Section(header: Text(state.description).font(.subheadline).foregroundColor(state.color).padding(.top)) {
									ForEach(connections, id: \.0) { key, value in
										ConnectionListItem(dbux: dbux, url: key, state: value, showReconnectButton: true, editMode:$isEditMode)
									}
								}
							}
						} else {
							ForEach(sortedConnections, id: \.0) { key, state in
								ConnectionListItem(dbux: dbux, url: key, state: state, showReconnectButton: false, editMode:$isEditMode)
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
