import Vision
import UIKit

/// Uses Apple's Vision framework to perform on-device OCR on a business card image.
struct TextRecognizer {

    /// Recognizes text in the given image and returns an array of recognized text lines.
    /// Processing happens on a background queue; the completion is called on a background thread.
    static func recognizeText(in image: UIImage, completion: @escaping ([String]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation] else {
                completion([])
                return
            }

            let lines: [String] = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }

            completion(lines)
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion([])
            }
        }
    }
}
