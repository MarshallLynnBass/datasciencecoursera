import Foundation

/// Parses an array of OCR-recognized text lines and populates a `ScannedContact`.
struct ContactParser {

    // MARK: - Public

    static func parse(lines: [String], into contact: ScannedContact) {
        var remainingLines: [String] = []

        var phones: [String] = []
        var emails: [String] = []
        var website: String = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let email = extractEmail(from: trimmed) {
                emails.append(email)
            } else if let phone = extractPhone(from: trimmed) {
                phones.append(phone)
            } else if let url = extractWebsite(from: trimmed) {
                website = url
            } else if looksLikeAddress(trimmed) {
                parseAddress(trimmed, into: contact)
            } else {
                remainingLines.append(trimmed)
            }
        }

        contact.phoneNumbers = phones.isEmpty ? [""] : phones
        contact.emailAddresses = emails.isEmpty ? [""] : emails
        contact.website = website

        // Heuristic: the first remaining line is likely the person's name,
        // the second is their title, and the third is the company.
        assignNameTitleCompany(from: remainingLines, into: contact)
    }

    // MARK: - Extraction Helpers

    private static func extractEmail(from text: String) -> String? {
        let pattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    private static func extractPhone(from text: String) -> String? {
        // Match common phone formats: +1 (555) 123-4567, 555.123.4567, etc.
        let pattern = #"[\+]?[\d\s\-\.\(\)]{7,20}"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Require at least 7 digits to be considered a phone number
        let digitCount = match.filter { $0.isNumber }.count
        guard digitCount >= 7 else { return nil }

        // Skip if the line also contains too many alpha characters (likely not a phone)
        let alphaCount = text.filter { $0.isLetter }.count
        if alphaCount > digitCount { return nil }

        return match
    }

    private static func extractWebsite(from text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("www.") || lower.contains("http://") || lower.contains("https://") {
            // Clean up and return
            let pattern = #"(https?://)?[\w.-]+\.[a-z]{2,}[/\w.-]*"#
            if let range = lower.range(of: pattern, options: .regularExpression) {
                return String(text[range])
            }
        }
        return nil
    }

    private static func looksLikeAddress(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Common address indicators
        let indicators = [
            "street", "st.", "ave", "avenue", "blvd", "boulevard",
            "drive", "dr.", "road", "rd.", "lane", "ln.",
            "suite", "ste.", "floor", "fl.",
        ]
        if indicators.contains(where: { lower.contains($0) }) { return true }

        // Pattern: starts with a number followed by words (e.g., "123 Main St")
        let addressPattern = #"^\d+\s+\w+"#
        if lower.range(of: addressPattern, options: .regularExpression) != nil {
            // Also check it has some common address-like content or a comma
            if lower.contains(",") || indicators.contains(where: { lower.contains($0) }) {
                return true
            }
        }

        // US state abbreviation + zip code pattern
        let stateZip = #"[A-Z]{2}\s+\d{5}"#
        if text.range(of: stateZip, options: .regularExpression) != nil { return true }

        return false
    }

    private static func parseAddress(_ text: String, into contact: ScannedContact) {
        // Try to split by commas
        let parts = text.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if parts.count >= 3 {
            contact.streetAddress = parts[0]
            contact.city = parts[1]

            // Last part may be "State ZIP" or "State ZIP Country"
            let lastPart = parts[parts.count - 1]
            parseStateZip(lastPart, into: contact)
        } else if parts.count == 2 {
            contact.streetAddress = parts[0]
            parseStateZip(parts[1], into: contact)
        } else {
            // Single line — store the whole thing as street address
            contact.streetAddress = text
        }
    }

    private static func parseStateZip(_ text: String, into contact: ScannedContact) {
        // Try "CA 90210" pattern
        let pattern = #"([A-Za-z\s]+?)\s+(\d{5}(?:-\d{4})?)"#
        if let match = text.range(of: pattern, options: .regularExpression) {
            let matched = String(text[match])
            let components = matched.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if components.count >= 2 {
                contact.state = components.dropLast().joined(separator: " ")
                contact.postalCode = components.last ?? ""
            }
        } else {
            // Fall back: treat as city or state
            if contact.city.isEmpty {
                contact.city = text
            } else {
                contact.state = text
            }
        }
    }

    // MARK: - Name / Title / Company

    private static func assignNameTitleCompany(from lines: [String], into contact: ScannedContact) {
        guard !lines.isEmpty else { return }

        // First line is most likely the name
        let nameParts = lines[0].components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if nameParts.count >= 2 {
            contact.firstName = nameParts[0]
            contact.lastName = nameParts.dropFirst().joined(separator: " ")
        } else {
            contact.firstName = lines[0]
        }

        // Second line — job title
        if lines.count >= 2 {
            contact.jobTitle = lines[1]
        }

        // Third line — company name
        if lines.count >= 3 {
            contact.company = lines[2]
        }

        // If only two lines, the second might be the company rather than title.
        // Heuristic: if it contains common title words, keep as title; otherwise treat as company.
        if lines.count == 2 {
            let titleKeywords = [
                "manager", "director", "engineer", "president", "vp",
                "ceo", "cto", "cfo", "coo", "chief", "officer",
                "developer", "designer", "analyst", "consultant",
                "specialist", "coordinator", "lead", "head", "senior",
                "junior", "associate", "partner", "founder", "owner",
            ]
            let lower = lines[1].lowercased()
            let isLikelyTitle = titleKeywords.contains(where: { lower.contains($0) })
            if !isLikelyTitle {
                contact.company = lines[1]
                contact.jobTitle = ""
            }
        }
    }
}
