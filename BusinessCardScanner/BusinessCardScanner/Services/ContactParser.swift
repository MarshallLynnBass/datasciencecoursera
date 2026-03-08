import Foundation

/// Parses an array of spatially-aware OCR text elements into a `ScannedContact`,
/// using NSDataDetector for structured data and spatial/size heuristics for names and titles.
struct ContactParser {

    // MARK: - Public

    static func parse(elements: [RecognizedTextElement], into contact: ScannedContact) {
        // Sort elements top-to-bottom by their vertical center (top of card first)
        let sorted = elements.sorted { $0.verticalCenter < $1.verticalCenter }

        var phones: [LabeledPhone] = []
        var emails: [String] = []
        var website: String = ""
        var addressLines: [String] = []

        // Track which elements are "consumed" by NSDataDetector so we know what's left
        var consumed = Set<Int>()

        // Combine all text for NSDataDetector (it works best on a full block of text).
        // But we also need per-element detection to know which element each match came from.
        for (index, element) in sorted.enumerated() {
            let text = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                consumed.insert(index)
                continue
            }

            let detectedTypes = detectData(in: text)

            for detection in detectedTypes {
                switch detection {
                case .phone(let number):
                    let label = inferPhoneLabel(
                        from: text,
                        nearby: nearbyText(for: index, in: sorted)
                    )
                    phones.append(LabeledPhone(number: number, label: label))
                    consumed.insert(index)

                case .email(let address):
                    emails.append(address)
                    consumed.insert(index)

                case .url(let urlString):
                    if website.isEmpty {
                        website = urlString
                    }
                    consumed.insert(index)

                case .address(let components):
                    if let street = components[.street] {
                        contact.streetAddress = street
                    }
                    if let city = components[.city] {
                        contact.city = city
                    }
                    if let state = components[.state] {
                        contact.state = state
                    }
                    if let zip = components[.zip] {
                        contact.postalCode = zip
                    }
                    if let country = components[.country] {
                        contact.country = country
                    }
                    consumed.insert(index)
                }
            }
        }

        contact.phoneNumbers = phones.isEmpty ? [LabeledPhone()] : phones
        contact.emailAddresses = emails.isEmpty ? [""] : emails
        contact.website = website

        // Gather unconsumed elements — these are candidates for name, title, company
        let remaining = sorted.enumerated()
            .filter { !consumed.contains($0.offset) }
            .map { $0.element }

        assignNameTitleCompany(from: remaining, allElements: sorted, into: contact)
    }

    // MARK: - NSDataDetector

    private enum DetectedData {
        case phone(String)
        case email(String)
        case url(String)
        case address([AddressKey: String])

        enum AddressKey {
            case street, city, state, zip, country
        }
    }

    private static func detectData(in text: String) -> [DetectedData] {
        var results: [DetectedData] = []

        let types: NSTextCheckingResult.CheckingType = [
            .phoneNumber, .link, .address
        ]

        guard let detector = try? NSDataDetector(types: types.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)

        let matches = detector.matches(in: text, options: [], range: range)

        for match in matches {
            if let phone = match.phoneNumber {
                results.append(.phone(phone))
            }

            if let url = match.url {
                let urlString = url.absoluteString
                // NSDataDetector classifies mailto: links as .link
                if urlString.hasPrefix("mailto:") {
                    let email = String(urlString.dropFirst("mailto:".count))
                    results.append(.email(email))
                } else {
                    results.append(.url(urlString))
                }
            }

            if let addressComponents = match.addressComponents {
                var parsed: [DetectedData.AddressKey: String] = [:]
                if let street = addressComponents[NSTextCheckingKey.street] {
                    parsed[.street] = street
                }
                if let city = addressComponents[NSTextCheckingKey.city] {
                    parsed[.city] = city
                }
                if let state = addressComponents[NSTextCheckingKey.state] {
                    parsed[.state] = state
                }
                if let zip = addressComponents[NSTextCheckingKey.zip] {
                    parsed[.zip] = zip
                }
                if let country = addressComponents[NSTextCheckingKey.country] {
                    parsed[.country] = country
                }
                if !parsed.isEmpty {
                    results.append(.address(parsed))
                }
            }
        }

        // Also check for emails via regex as a fallback — NSDataDetector sometimes
        // wraps them as mailto: URLs, but can miss bare email addresses.
        if !results.contains(where: { if case .email = $0 { return true }; return false }) {
            let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
            if let emailRange = text.range(of: emailPattern, options: .regularExpression) {
                results.append(.email(String(text[emailRange])))
            }
        }

        return results
    }

    // MARK: - Phone Label Detection

    /// Maps of keywords to phone label types, checked against the line containing
    /// the phone number and the lines immediately above/below it.
    private static let phoneLabelMap: [(keywords: [String], label: LabeledPhone.PhoneLabel)] = [
        (["mobile", "cell", "m:", "mob"], .mobile),
        (["fax", "f:", "facsimile"], .fax),
        (["home", "h:", "personal"], .home),
        (["direct", "d:", "dir"], .direct),
        (["main", "general", "switchboard"], .main),
        (["office", "work", "o:", "w:", "tel", "telephone", "phone", "ph:", "t:"], .work),
    ]

    private static func inferPhoneLabel(from lineText: String, nearby: [String]) -> LabeledPhone.PhoneLabel {
        let allText = ([lineText] + nearby).joined(separator: " ").lowercased()

        for entry in phoneLabelMap {
            for keyword in entry.keywords {
                if allText.contains(keyword) {
                    return entry.label
                }
            }
        }

        return .work // default
    }

    /// Returns the text of the elements immediately before and after `index`.
    private static func nearbyText(for index: Int, in elements: [RecognizedTextElement]) -> [String] {
        var texts: [String] = []
        if index > 0 {
            texts.append(elements[index - 1].text)
        }
        if index < elements.count - 1 {
            texts.append(elements[index + 1].text)
        }
        return texts
    }

    // MARK: - Name / Title / Company (spatial + size heuristics)

    private static let titleKeywords = [
        "manager", "director", "engineer", "president", "vp", "vice president",
        "ceo", "cto", "cfo", "coo", "cio", "cmo",
        "chief", "officer", "executive",
        "developer", "designer", "analyst", "consultant", "architect",
        "specialist", "coordinator", "lead", "head", "senior", "sr.",
        "junior", "jr.", "associate", "partner", "founder", "co-founder",
        "owner", "principal", "supervisor", "administrator", "strategist",
        "marketing", "sales", "operations", "accounting",
    ]

    private static func assignNameTitleCompany(
        from remaining: [RecognizedTextElement],
        allElements: [RecognizedTextElement],
        into contact: ScannedContact
    ) {
        guard !remaining.isEmpty else { return }

        // --- Step 1: Find the largest text element — most likely the person's name ---
        let maxHeight = remaining.map(\.relativeHeight).max() ?? 0
        // Consider elements "largest" if they are within 85% of the max height
        let largestThreshold = maxHeight * 0.85

        let largestElements = remaining.filter { $0.relativeHeight >= largestThreshold }

        // Among the largest elements, prefer the one nearest the top
        let nameElement = largestElements.min(by: { $0.verticalCenter < $1.verticalCenter })

        // --- Step 2: Classify remaining elements ---
        var nameCandidate: String?
        var titleCandidate: String?
        var companyCandidates: [String] = []

        for element in remaining {
            let text = element.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if let nameEl = nameElement, element.text == nameEl.text,
               element.boundingBox == nameEl.boundingBox {
                nameCandidate = text
                continue
            }

            if isLikelyJobTitle(text) && titleCandidate == nil {
                titleCandidate = text
            } else {
                companyCandidates.append(text)
            }
        }

        // If we didn't get a name from size heuristic, fall back to top-most remaining
        if nameCandidate == nil {
            nameCandidate = remaining.first?.text
            // Remove it from company candidates if it ended up there
            if let name = nameCandidate {
                companyCandidates.removeAll { $0 == name }
            }
        }

        // Assign name
        if let name = nameCandidate {
            let parts = name.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 2 {
                contact.firstName = parts[0]
                contact.lastName = parts.dropFirst().joined(separator: " ")
            } else {
                contact.firstName = name
            }
        }

        // Assign title
        contact.jobTitle = titleCandidate ?? ""

        // Assign company — use the first company candidate that isn't the title
        // Prefer a candidate that is near the top of the card (often right below the name)
        if let company = companyCandidates.first {
            contact.company = company
        }
    }

    private static func isLikelyJobTitle(_ text: String) -> Bool {
        let lower = text.lowercased()
        return titleKeywords.contains(where: { lower.contains($0) })
    }
}
