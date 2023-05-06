//
//  CachedAsyncView.swift
//  topaz
//
//  Created by Tanner Silva on 4/27/23.
//

import Foundation
import SwiftUI

struct UnstoredAsyncImage<Content: View, Placeholder: View>: View {
	@ObservedObject var viewModel: CustomAsyncImageViewModel
	private let url: URL
	private let placeholder: () -> Placeholder
	private let content: (Image) -> Content

	init(url: URL, @ViewBuilder content: @escaping (_ image: Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
		self.url = url
		self.placeholder = placeholder
		self.content = content
		self.viewModel = ImageRequestActor.globalRequestor.getViewModel(url: url)
	}

   var body: some View {
	   Group {
		   if let image = viewModel.image {
			   content(image)
		   } else {
			   placeholder()
		   }
	   }
	   .task(id: url) { @MainActor in

		   await viewModel.loadImage()
	   }
   }
}

class ImageRequestActor {
	static let globalRequestor = ImageRequestActor()
	private var ongoingRequests: [URL: CustomAsyncImageViewModel] = [:]

	@MainActor func getViewModel(url: URL) -> CustomAsyncImageViewModel {
		if let existingViewModel = ongoingRequests[url] {
			return existingViewModel
		} else {
			let viewModel = CustomAsyncImageViewModel(url: url)
			ongoingRequests[url] = viewModel
			return viewModel
		}
	}
}


class CustomAsyncImageViewModel: ObservableObject {
	@Published var image: Image? = nil
	private let url: URL
	private static let imageRequestActor = ImageRequestActor()
	
	init(url: URL) {
		self.url = url
	}
	
	func loadImage() async {
		if image == nil {
			do {
				let imageData = try await HTTP.getContent(url: url)
				if let uiImage = UIImage(data: imageData.0) {
					image = Image(uiImage: uiImage)
				}
			} catch {
				print("Error loading image: \(error)")
			}
		}
	}
}


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
