//
//  URLPreview.swift
//  topaz
//
//  Created by Tanner Silva on 5/10/23.
//

import Foundation
import SwiftUI

struct URLPreview: View {
	let url: URL

	var body: some View {
		VStack(alignment: .leading) {
			HStack {
				Image(systemName: "link.circle.fill")
					.foregroundColor(.blue)
				Text(url.absoluteString)
					.font(.headline)
					.lineLimit(1)
			}
			Text("Website Preview")
				.font(.subheadline)
				.foregroundColor(.gray)
		}
		.padding()
		.background(Color(.secondarySystemBackground))
		.cornerRadius(10)
		.onTapGesture {
			UIApplication.shared.open(url)
		}
	}
}
