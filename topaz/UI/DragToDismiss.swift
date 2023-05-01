//
//  DragToDismiss.swift
//  topaz
//
//  Created by Tanner Silva on 5/1/23.
//

import Foundation
import SwiftUI

struct DragToDismiss: ViewModifier {
	@Environment(\.presentationMode) var presentationMode
	@GestureState private var dragState = DragState.inactive

	enum DragState {
		case inactive
		case dragging(translation: CGSize)
		
		var translation: CGSize {
			switch self {
			case .inactive:
				return .zero
			case .dragging(let translation):
				return translation
			}
		}
		
		var isDragging: Bool {
			switch self {
			case .inactive:
				return false
			case .dragging:
				return true
			}
		}
	}
	
	func body(content: Content) -> some View {
		content
			.offset(x: self.dragState.translation.width)
			.gesture(
				DragGesture()
					.updating($dragState) { drag, state, transaction in
						state = .dragging(translation: drag.translation)
					}
					.onEnded { value in
						if value.translation.width > UIScreen.main.bounds.width * 0.3 {
							self.presentationMode.wrappedValue.dismiss()
						}
					}
			)
	}
}
