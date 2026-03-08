import Vision
import UIKit

/// A single recognized text element with its string, bounding box, and estimated font size.
struct RecognizedTextElement {
    let text: String
    /// Bounding box in normalized coordinates (0...1), origin at bottom-left (Vision convention).
    let boundingBox: CGRect
    /// Estimated relative height of the text (proxy for font size).
    let relativeHeight: CGFloat

    /// Vertical center in top-origin coordinates (0 = top of card, 1 = bottom).
    var verticalCenter: CGFloat {
        1.0 - (boundingBox.origin.y + boundingBox.height / 2.0)
    }

    /// Horizontal center (0 = left, 1 = right).
    var horizontalCenter: CGFloat {
        boundingBox.origin.x + boundingBox.width / 2.0
    }
}

/// Uses Apple's Vision framework to perform on-device OCR on a business card image,
/// returning rich spatial data for each recognized text element.
struct TextRecognizer {

    /// Recognizes text in the given image and returns `RecognizedTextElement` values
    /// that include the string, bounding box, and relative text height.
    /// Processing happens on a background queue; the completion is called on a background thread.
    static func recognizeText(in image: UIImage, completion: @escaping ([RecognizedTextElement]) -> Void) {
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

            let elements: [RecognizedTextElement] = observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox
                return RecognizedTextElement(
                    text: candidate.string,
                    boundingBox: box,
                    relativeHeight: box.height
                )
            }

            completion(elements)
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

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
