import Foundation

/// Holds the parsed contact fields extracted from a business card.
class ScannedContact: ObservableObject {
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var jobTitle: String = ""
    @Published var company: String = ""
    @Published var phoneNumbers: [LabeledPhone] = [LabeledPhone()]
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

/// A phone number paired with a label (e.g. "Mobile", "Work", "Fax").
struct LabeledPhone: Identifiable {
    let id = UUID()
    var number: String = ""
    var label: PhoneLabel = .work

    enum PhoneLabel: String, CaseIterable, Identifiable {
        case mobile = "Mobile"
        case work = "Work"
        case home = "Home"
        case main = "Main"
        case direct = "Direct"
        case fax = "Fax"
        case other = "Other"

        var id: String { rawValue }
    }
}
