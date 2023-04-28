//
//  CachedAsyncView.swift
//  topaz
//
//  Created by Tanner Silva on 4/27/23.
//

import Foundation
import SwiftUI

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
	@StateObject private var viewModel: CachedAsyncImageViewModel
	private let content: (_ image: Image) -> Content
	private let placeholder: Placeholder

	init(url: URL, imageCache: ImageCache, @ViewBuilder content: @escaping (_ image: Image) -> Content, @ViewBuilder placeholder: () -> Placeholder) {
		_viewModel = StateObject(wrappedValue: CachedAsyncImageViewModel(url: url, imageCache: imageCache))
		self.content = content
		self.placeholder = placeholder()
	}

	init(url: URL, imageCache: ImageCache, @ViewBuilder content: @escaping (_ image: Image) -> Content) {
		self.init(url: url, imageCache: imageCache, content: content, placeholder: { ProgressView() as! Placeholder })
	}

	var body: some View {
		Group {
			if let uiImage = viewModel.image {
				content(Image(uiImage: uiImage))
			} else {
				placeholder
			}
		}
		.onAppear {
			Task {
				await viewModel.loadImage()
			}
		}
	}
}

final class CachedAsyncImageViewModel: ObservableObject {
	@Published var image: UIImage?
	private let url: URL
	private let imageCache: ImageCache

	init(url: URL, imageCache: ImageCache) {
		self.url = url
		self.imageCache = imageCache
	}

	func loadImage() async {
		guard image == nil else { return }
		do {
			let getImage = try await imageCache.loadImage(from: url, using: loadContentTypeAndImageData)
			Task.detached { @MainActor [weak self, gi = getImage] in
				guard let self = self else { return }
				self.image = gi
			}
		} catch {
			print("Error loading image: \(error)")
		}
	}

	private func loadContentTypeAndImageData(from url: URL) async throws -> (String, Data) {
		let (data, contentTypeOptional) = try await HTTP.getContent(url: url)
		guard let contentType = contentTypeOptional else {
			throw NSError(domain: "Missing content type", code: -1, userInfo: nil)
		}
		return (contentType, data)
	}
}
