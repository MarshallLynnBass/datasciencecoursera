import SwiftUI

struct HomeView: View {
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var navigateToReview = false
    @StateObject private var contact = ScannedContact()
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()

                Image(systemName: "person.crop.rectangle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundColor(.accentColor)

                Text("Business Card Scanner")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Take a photo of a business card to create a new contact.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if isProcessing {
                    ProgressView("Scanning card...")
                        .padding()
                } else {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Scan Business Card", systemImage: "camera.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 40)
                }

                Spacer()
            }
            .navigationDestination(isPresented: $navigateToReview) {
                ContactReviewView(contact: contact) {
                    // Reset state after save or cancel
                    resetState()
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraView { image in
                    guard let image = image else { return }
                    processImage(image)
                }
            }
        }
    }

    private func processImage(_ image: UIImage) {
        isProcessing = true
        let newContact = ScannedContact()

        TextRecognizer.recognizeText(in: image) { recognizedLines in
            DispatchQueue.main.async {
                ContactParser.parse(lines: recognizedLines, into: newContact)
                self.contact = newContact
                self.isProcessing = false
                self.navigateToReview = true
                // Image is not stored — it goes out of scope here
            }
        }
    }

    private func resetState() {
        capturedImage = nil
        navigateToReview = false
    }
}
