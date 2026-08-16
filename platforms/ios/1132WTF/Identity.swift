import Foundation

/// Throwaway identity details for joining as somebody the host has not blocked.
///
/// A display name is often all a manual host-side removal was keyed on, so a
/// fresh one is worth trying before anything more drastic.
enum Identity {
    private static let firstNames = [
        "Alex", "Sam", "Jordan", "Casey", "Riley", "Quinn", "Avery", "Morgan",
        "Taylor", "Jamie", "Drew", "Reese", "Kai", "Rowan", "Sky", "Finn",
    ]

    private static let lastNames = [
        "Chen", "Patel", "Garcia", "Kim", "Novak", "Silva", "Haddad", "Okafor",
        "Ivanov", "Dubois", "Rossi", "Nakamura", "Andersson", "Costa", "Weber",
    ]

    static func displayName() -> String {
        let first = firstNames.randomElement() ?? "Alex"
        let last = lastNames.randomElement() ?? "Chen"
        return "\(first) \(last)"
    }

    /// A plus-address suggestion for making a new Zoom account on the same
    /// mailbox. Most providers deliver anything after a "+" to the same inbox
    /// while Zoom treats it as a different address.
    static func emailAlias(base: String) -> String {
        var mailbox = base
        var domain = "gmail.com"
        if let at = base.firstIndex(of: "@") {
            mailbox = String(base[base.startIndex..<at])
            domain = String(base[base.index(after: at)...])
        }
        return "\(mailbox)+\(suffix())@\(domain)"
    }

    private static func suffix() -> String {
        // Short and unambiguous: no letters that read as digits.
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        let tail = (0..<4).map { _ in String(alphabet.randomElement() ?? "x") }.joined()
        return "wtf\(tail)"
    }
}
