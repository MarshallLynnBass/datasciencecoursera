import Foundation

/// Parses an array of OCR-recognized text lines into a `ScannedContact`,
/// using NSDataDetector for structured data and heuristics for names and titles.
struct ContactParser {

    // MARK: - Public

    static func parse(lines: [String], into contact: ScannedContact) {
        var phones: [LabeledPhone] = []
        var emails: [String] = []
        var website: String = ""

        // Track which lines are "consumed" by NSDataDetector so we know what's left
        var consumed = Set<Int>()

        for (index, rawLine) in lines.enumerated() {
            let text = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
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
                        nearby: nearbyText(for: index, in: lines)
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

        // Gather unconsumed lines — these are candidates for name, title, company
        let remaining = lines.enumerated()
            .filter { !consumed.contains($0.offset) }
            .map { $0.element.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        assignNameTitleCompany(from: remaining, into: contact)
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

    /// Returns the text of the lines immediately before and after `index`.
    private static func nearbyText(for index: Int, in lines: [String]) -> [String] {
        var texts: [String] = []
        if index > 0 {
            texts.append(lines[index - 1])
        }
        if index < lines.count - 1 {
            texts.append(lines[index + 1])
        }
        return texts
    }

    // MARK: - Name / Title / Company

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

    private static func assignNameTitleCompany(from lines: [String], into contact: ScannedContact) {
        guard !lines.isEmpty else { return }

        // First remaining line is most likely the name
        let nameParts = lines[0].components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if nameParts.count >= 2 {
            contact.firstName = nameParts[0]
            contact.lastName = nameParts.dropFirst().joined(separator: " ")
        } else {
            contact.firstName = lines[0]
        }

        // Classify remaining lines as title or company
        var titleCandidate: String?
        var companyCandidate: String?

        for line in lines.dropFirst() {
            if isLikelyJobTitle(line) && titleCandidate == nil {
                titleCandidate = line
            } else if companyCandidate == nil {
                companyCandidate = line
            }
        }

        contact.jobTitle = titleCandidate ?? ""

        // If only two remaining lines and neither matched title keywords,
        // the second line is more likely the company than the title
        if lines.count == 2 && titleCandidate == nil {
            contact.company = lines[1]
        } else {
            contact.company = companyCandidate ?? ""
        }
    }

    private static func isLikelyJobTitle(_ text: String) -> Bool {
        let lower = text.lowercased()
        return titleKeywords.contains(where: { lower.contains($0) })
    }
}
