//
//  UIImage.swift
//  topaz
//
//  Created by Tanner Silva on 4/30/23.
//

import Foundation
import UIKit

extension UIImage {
	
	func resizedImage(maxPixelsInLargestDimension: CGFloat) -> UIImage {
		let originalSize = self.size
		let largestDimension = max(originalSize.width, originalSize.height)

		if largestDimension <= maxPixelsInLargestDimension {
			return self
		}

		let scaleRatio = maxPixelsInLargestDimension / largestDimension
		let newSize = CGSize(width: originalSize.width * scaleRatio, height: originalSize.height * scaleRatio)

		UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
		self.draw(in: CGRect(origin: .zero, size: newSize))
		let resizedImage = UIGraphicsGetImageFromCurrentImageContext()!
		UIGraphicsEndImageContext()

		return resizedImage
	}
	
	func exportData() -> Data? {
		return self.jpegData(compressionQuality:1)
	}
	
	func resizedAndCompressedImage(maxPixelsInLargestDimension: CGFloat, compressionQuality: Double) -> UIImage? {
		let resizedImage = self.resizedImage(maxPixelsInLargestDimension: maxPixelsInLargestDimension)
		guard let compressedData = resizedImage.jpegData(compressionQuality: compressionQuality) else {
			return nil
		}
		return UIImage(data: compressedData)
	}
}
