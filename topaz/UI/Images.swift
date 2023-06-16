//
//  CachedAsyncView.swift
//  topaz
//
//  Created by Tanner Silva on 4/27/23.
//

import Foundation
import SwiftUI
import QuickLMDB

extension UI {
	struct Images {
		enum Error:Swift.Error {
			case invalidImageData
			case compressionError
		}
		struct AssetPipeline {
			struct Configuration {
				struct Compression {
					let maxPixelsInLargestDimension:CGFloat
					let compressionQuality:Double
				}
				let compression:Compression?
				let storage:DBUX.AssetStore?
			}
			
			// manages the logistics of various pipeline requests
			public class RequestActor {
				let configuration:Configuration
				@MainActor private var ongoingRequests: [URL: ViewModel] = [:]
				public init(configuration:Configuration) {
					self.configuration = configuration
				}
				@MainActor fileprivate func getViewModel(url: URL) -> ViewModel {
					if let existingViewModel = ongoingRequests[url] {
						return existingViewModel
					} else {
						let viewModel = ViewModel(url: url, configuration:configuration)
						ongoingRequests[url] = viewModel
						return viewModel
					}
				}
			}
			
			fileprivate class ViewModel: ObservableObject {
				enum FetchState {
					case idle
					case fetching
					case complete(Result<Image, Swift.Error>)
				}
				private let configuration:Configuration
				@MainActor private var fetchTask:Task<Void, Never>? = nil
				@MainActor @Published var state:FetchState = .idle
				private let url: URL
				
				fileprivate init(url:URL, configuration:Configuration) {
					self.url = url
					self.configuration = configuration
				}
				
				@MainActor func hit() {
					if let hasConfiguration = self.configuration.storage {
						Task.detached { [getStore = hasConfiguration, urlstr = url.absoluteString] in
							let makeURLHash = try DBUX.URLHash(urlstr)
							let makeHit = DBUX.AssetStore.Hit(urlHash:makeURLHash, date:DBUX.Date())
							await getStore.holder.append(element: makeHit)
						}
					}
					
				}
				
				@MainActor func loadImage() async {
					guard case .idle = self.state else { return }
					print("\(self.url.absoluteString)")
					let asHash = try! DBUX.URLHash(self.url.absoluteString)
					self.state = .fetching
					
					func launchTask() {
						self.fetchTask = Task.detached { [weak self, getURL = url, conf = self.configuration, urlH = asHash] in
							do {
								let imageData = try await HTTP.getContent(url:getURL)
								guard let uiImage = UIImage(data:imageData.0) else {
									throw UI.Images.Error.invalidImageData
								}
								let finalImage:UIImage
								if let hasCompressionSettings = conf.compression {
									guard let successfulCompression = uiImage.resizedAndCompressedImage(maxPixelsInLargestDimension: hasCompressionSettings.maxPixelsInLargestDimension, compressionQuality:hasCompressionSettings.compressionQuality) else {
										throw Error.compressionError
									}
									finalImage = successfulCompression
								} else {
									finalImage = uiImage
								}
								if let hasStore = conf.storage, let hasjpgData = finalImage.jpegData(compressionQuality: 1.0) {
									try hasStore.storeAsset(hasjpgData, for: urlH)
								}
								Task.detached { @MainActor [weak self, imgDat = Image(uiImage:finalImage)] in
									self?.fetchTask = nil
									self?.state = .complete(.success(imgDat))
								}
							} catch let error {
								Task.detached { @MainActor [weak self, errorFound = error] in
									self?.fetchTask = nil
									self?.state = .complete(.failure(errorFound))
								}
							}
						}
					}
					
					if let hasStorage = self.configuration.storage {
						do {
							let getAsset = try await hasStorage.getAsset(asHash)
							if let hasImage = UIImage(data:getAsset) {
								self.state = .complete(.success(Image(uiImage:hasImage)))
								return
							}
						} catch LMDBError.notFound {
							launchTask()
						} catch { return }
					} else {
						launchTask()
					}
				}
				
				deinit {
					if let hasTask = fetchTask {
						hasTask.cancel()
					}
				}
			}
			
			struct AsyncImage<Content: View, Placeholder: View>: View {
				@ObservedObject private var viewModel: ViewModel
				private let url: URL
				private let placeholder: () -> Placeholder
				private let content: (Image) -> Content
				
				init(url: URL, actor:RequestActor, @ViewBuilder content: @escaping (_ image: Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
					self.url = url
					self.placeholder = placeholder
					self.content = content
					self.viewModel = actor.getViewModel(url: url)
				}
				
				var body: some View {
					Group {
						switch viewModel.state {
						case .complete(let results):
							switch results {
							case .success(let res):
								content(res)
							case .failure(_):
								placeholder()
							}
						default:
							placeholder()
						}
					}.onAppear() {
						self.viewModel.hit()
					}.task() {
						await viewModel.loadImage()
					}
				}
			}
		}
	}
}
