import Contacts

/// Saves a `ScannedContact` to the device's address book using the Contacts framework.
struct ContactSaver {

    enum SaveError: LocalizedError {
        case accessDenied
        case saveFailed(Error)

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Contacts access was denied. Please allow access in Settings > Privacy > Contacts."
            case .saveFailed(let error):
                return "Failed to save contact: \(error.localizedDescription)"
            }
        }
    }

    static func save(_ contact: ScannedContact, completion: @escaping (Result<Void, SaveError>) -> Void) {
        let store = CNContactStore()

        store.requestAccess(for: .contacts) { granted, error in
            guard granted else {
                completion(.failure(.accessDenied))
                return
            }

            let cnContact = CNMutableContact()

            // Name
            cnContact.givenName = contact.firstName
            cnContact.familyName = contact.lastName

            // Work info
            cnContact.jobTitle = contact.jobTitle
            cnContact.organizationName = contact.company

            // Phone numbers
            cnContact.phoneNumbers = contact.phoneNumbers
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: $0)) }

            // Email addresses
            cnContact.emailAddresses = contact.emailAddresses
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { CNLabeledValue(label: CNLabelWork, value: $0 as NSString) }

            // Postal address
            let address = CNMutablePostalAddress()
            address.street = contact.streetAddress
            address.city = contact.city
            address.state = contact.state
            address.postalCode = contact.postalCode
            address.country = contact.country

            let hasAddress = ![
                contact.streetAddress, contact.city,
                contact.state, contact.postalCode,
            ].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }

            if hasAddress {
                cnContact.postalAddresses = [
                    CNLabeledValue(label: CNLabelWork, value: address)
                ]
            }

            // Website
            if !contact.website.trimmingCharacters(in: .whitespaces).isEmpty {
                cnContact.urlAddresses = [
                    CNLabeledValue(label: CNLabelWork, value: contact.website as NSString)
                ]
            }

            // Save
            let saveRequest = CNSaveRequest()
            saveRequest.add(cnContact, toContainerWithIdentifier: nil)

            do {
                try store.execute(saveRequest)
                completion(.success(()))
            } catch {
                completion(.failure(.saveFailed(error)))
            }
        }
    }
}
