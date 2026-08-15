import Foundation

/// Turns whatever the user pasted into a Zoom web client link.
///
/// The web client runs in a web view, so it carries none of the native app's
/// device identity. On iOS that makes it the only level 1132.WTF can carry out
/// entirely on its own.
enum MeetingLink {
    static let joinPage = "https://zoom.us/join"

    /// - Parameter input: a meeting id, a zoom.us link, or a zoommtg:// link.
    /// - Returns: a web client URL, or the generic join page when no id is found.
    static func webClientURL(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return joinPage }

        let password = extractPassword(from: trimmed)

        guard let id = meetingID(from: trimmed) else {
            // Not recognisable as a meeting, but if it is already a URL then let
            // the web view deal with it rather than throwing it away.
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                return trimmed
            }
            return joinPage
        }

        var url = "https://zoom.us/wc/join/\(id)"
        if let password, !password.isEmpty {
            url += "?pwd=\(password)"
        }
        return url
    }

    /// Pulls the digits of a meeting id out of free-form text.
    static func meetingID(from input: String) -> String? {
        // A /j/<id> or /wc/join/<id> path segment is the most reliable signal, so
        // look for it before falling back to any run of digits.
        if let match = firstGroup(in: input, pattern: "/(?:j|wc/join|s)/([0-9]{9,11})") {
            return match
        }

        // Meeting ids are often written with spaces or dashes between groups.
        if let loose = firstGroup(in: input, pattern: "([0-9][0-9\\s-]{7,20}[0-9])") {
            let digits = loose.filter(\.isNumber)
            if digits.count >= 9 && digits.count <= 11 {
                return digits
            }
        }
        return nil
    }

    private static func extractPassword(from input: String) -> String? {
        firstGroup(in: input, pattern: "[?&]pwd=([^&\\s]+)")
    }

    private static func firstGroup(in input: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(input.startIndex..., in: input)
        guard let match = regex.firstMatch(in: input, range: range),
              match.numberOfRanges > 1,
              let group = Range(match.range(at: 1), in: input)
        else {
            return nil
        }
        return String(input[group])
    }
}
