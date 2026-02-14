import Foundation

/// Holds the parsed contact fields extracted from a business card.
class ScannedContact: ObservableObject {
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var jobTitle: String = ""
    @Published var company: String = ""
    @Published var phoneNumbers: [String] = [""]
    @Published var emailAddresses: [String] = [""]
    @Published var streetAddress: String = ""
    @Published var city: String = ""
    @Published var state: String = ""
    @Published var postalCode: String = ""
    @Published var country: String = ""
    @Published var website: String = ""

    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }
}
