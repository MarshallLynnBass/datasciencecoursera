import SwiftUI

/// Displays all parsed contact fields for review and editing before saving.
struct ContactReviewView: View {
    @ObservedObject var contact: ScannedContact
    @Environment(\.dismiss) private var dismiss
    @State private var showSaveAlert = false
    @State private var saveError: String?
    @State private var showErrorAlert = false

    /// Called after the user saves or cancels — lets the parent reset state.
    var onDismiss: () -> Void

    var body: some View {
        Form {
            Section(header: Text("Name")) {
                TextField("First Name", text: $contact.firstName)
                    .textContentType(.givenName)
                TextField("Last Name", text: $contact.lastName)
                    .textContentType(.familyName)
            }

            Section(header: Text("Work")) {
                TextField("Job Title", text: $contact.jobTitle)
                    .textContentType(.jobTitle)
                TextField("Company", text: $contact.company)
                    .textContentType(.organizationName)
            }

            Section(header: Text("Phone Numbers")) {
                ForEach(contact.phoneNumbers.indices, id: \.self) { index in
                    HStack {
                        TextField("Phone", text: $contact.phoneNumbers[index])
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                        if contact.phoneNumbers.count > 1 {
                            Button(role: .destructive) {
                                contact.phoneNumbers.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                Button {
                    contact.phoneNumbers.append("")
                } label: {
                    Label("Add Phone Number", systemImage: "plus.circle.fill")
                }
            }

            Section(header: Text("Email Addresses")) {
                ForEach(contact.emailAddresses.indices, id: \.self) { index in
                    HStack {
                        TextField("Email", text: $contact.emailAddresses[index])
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                        if contact.emailAddresses.count > 1 {
                            Button(role: .destructive) {
                                contact.emailAddresses.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                Button {
                    contact.emailAddresses.append("")
                } label: {
                    Label("Add Email Address", systemImage: "plus.circle.fill")
                }
            }

            Section(header: Text("Address")) {
                TextField("Street", text: $contact.streetAddress)
                    .textContentType(.streetAddressLine1)
                TextField("City", text: $contact.city)
                    .textContentType(.addressCity)
                TextField("State", text: $contact.state)
                    .textContentType(.addressState)
                TextField("ZIP Code", text: $contact.postalCode)
                    .textContentType(.postalCode)
                TextField("Country", text: $contact.country)
                    .textContentType(.countryName)
            }

            Section(header: Text("Other")) {
                TextField("Website", text: $contact.website)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
            }
        }
        .navigationTitle("Review Contact")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    onDismiss()
                    dismiss()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveContact()
                }
                .fontWeight(.semibold)
            }
        }
        .alert("Contact Saved", isPresented: $showSaveAlert) {
            Button("OK") {
                onDismiss()
                dismiss()
            }
        } message: {
            Text("\(contact.fullName) has been added to your contacts.")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "An unknown error occurred while saving the contact.")
        }
    }

    private func saveContact() {
        ContactSaver.save(contact) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    showSaveAlert = true
                case .failure(let error):
                    saveError = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}
