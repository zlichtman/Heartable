@preconcurrency import UIKit
import SwiftUI

/// UIKit's camera capture bridged into SwiftUI. The captured image is returned
/// as source data only; EditProfile owns the shared downscale/JPEG/upload path.
struct ProfilePhotoCameraPicker: UIViewControllerRepresentable {
    let onImageData: @MainActor (Data) -> Void
    let onCancel: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageData: onImageData, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
        UINavigationControllerDelegate {
        private let onImageData: @MainActor (Data) -> Void
        private let onCancel: @MainActor () -> Void

        init(
            onImageData: @escaping @MainActor (Data) -> Void,
            onCancel: @escaping @MainActor () -> Void
        ) {
            self.onImageData = onImageData
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info:
                [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 1) else {
                onCancel()
                return
            }
            onImageData(data)
        }

        func imagePickerControllerDidCancel(
            _ picker: UIImagePickerController
        ) {
            onCancel()
        }
    }
}
