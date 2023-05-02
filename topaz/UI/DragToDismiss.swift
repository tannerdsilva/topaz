//
//  DragToDismiss.swift
//  topaz
//
//  Created by Tanner Silva on 5/1/23.
//

import Foundation
import SwiftUI

class SwipeToDismissState: ObservableObject {
	@Published var isActive: Bool = false
}

struct DragToDismiss: ViewModifier {
	@Environment(\.presentationMode) var presentationMode
	@GestureState private var dragState = DragState.inactive
	var threshold: CGFloat

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
		GeometryReader { geometry in
			content
				.gesture(
					DragGesture()
						.updating($dragState) { drag, state, transaction in
							state = .dragging(translation: drag.translation)
						}
						.onEnded { value in
							let width = geometry.size.width
							if value.translation.width > width * threshold {
								self.presentationMode.wrappedValue.dismiss()
							}
						}
				)
		}
	}
}
