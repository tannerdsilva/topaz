import SwiftUI

struct ImagePicker: UIViewControllerRepresentable {
	@Binding var image: UIImage?
	@Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

	class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
		@Binding var image: UIImage?
		var presentationMode: Binding<PresentationMode>

		init(image: Binding<UIImage?>, presentationMode: Binding<PresentationMode>) {
			_image = image
			self.presentationMode = presentationMode
		}

		func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
			let uiImage = info[UIImagePickerController.InfoKey.originalImage] as! UIImage
			image = uiImage
			presentationMode.wrappedValue.dismiss()
		}

		func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
			presentationMode.wrappedValue.dismiss()
		}
	}

	func makeCoordinator() -> Coordinator {
		return Coordinator(image: $image, presentationMode: presentationMode)
	}

	func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
		let picker = UIImagePickerController()
		picker.delegate = context.coordinator
		return picker
	}

	func updateUIViewController(_ uiViewController: UIImagePickerController, context: UIViewControllerRepresentableContext<ImagePicker>) {
	}
}
