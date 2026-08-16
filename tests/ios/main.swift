// Tests for the parts of the iOS app that use no Apple UI frameworks.
//
// MeetingLink and Identity import only Foundation, so they compile and run on
// Linux with the open-source Swift toolchain. The cases mirror the Android
// suite exactly, which is how the two platforms are kept from drifting apart on
// something as easy to get subtly wrong as meeting link parsing.
//
// Run through tests/test_ios_logic.sh.

import Foundation

var passed = 0
var failed = 0

func pass(_ description: String) {
    passed += 1
    print("  ok    \(description)")
}

func fail(_ description: String, _ detail: String) {
    failed += 1
    print("  FAIL  \(description)")
    print("        \(detail)")
}

func checkURL(_ description: String, _ input: String, _ expected: String) {
    let actual = MeetingLink.webClientURL(from: input)
    if actual == expected {
        pass(description)
    } else {
        fail(description, "expected \(expected) but got \(actual)")
    }
}

func checkID(_ description: String, _ input: String, _ expected: String?) {
    let actual = MeetingLink.meetingID(from: input)
    if actual == expected {
        pass(description)
    } else {
        fail(description, "expected \(expected ?? "nil") but got \(actual ?? "nil")")
    }
}

func check(_ description: String, _ condition: Bool) {
    if condition {
        pass(description)
    } else {
        fail(description, "condition was false")
    }
}

print("")
print("1132.WTF iOS logic tests")
print("")

print("meeting link to web client URL")
checkURL("a bare meeting id", "1234567890",
         "https://zoom.us/wc/join/1234567890")
checkURL("an id written with spaces", "123 4567 890",
         "https://zoom.us/wc/join/1234567890")
checkURL("an id written with dashes", "123-4567-890",
         "https://zoom.us/wc/join/1234567890")
checkURL("a standard join link", "https://zoom.us/j/1234567890",
         "https://zoom.us/wc/join/1234567890")
checkURL("a regional join link", "https://us02web.zoom.us/j/98765432101",
         "https://zoom.us/wc/join/98765432101")
checkURL("a link with a password", "https://zoom.us/j/1234567890?pwd=AbC123",
         "https://zoom.us/wc/join/1234567890?pwd=AbC123")
checkURL("a zoommtg deep link", "zoommtg://zoom.us/join?confno=1234567890",
         "https://zoom.us/wc/join/1234567890")
checkURL("a web client link already", "https://zoom.us/wc/join/1234567890",
         "https://zoom.us/wc/join/1234567890")
checkURL("surrounding whitespace", "  1234567890  ",
         "https://zoom.us/wc/join/1234567890")

print("")
print("input that is not a meeting")
checkURL("empty input falls back to the join page", "", MeetingLink.joinPage)
checkURL("words fall back to the join page", "hello there", MeetingLink.joinPage)
checkURL("too few digits falls back to the join page", "12345", MeetingLink.joinPage)
checkURL("an unrelated URL is passed through", "https://example.com/foo",
         "https://example.com/foo")

print("")
print("meeting id extraction")
checkID("finds an id in a sentence", "join 1234567890 please", "1234567890")
checkID("prefers the path segment", "https://zoom.us/j/1234567890", "1234567890")
checkID("returns nil when absent", "no numbers here", nil)
checkID("rejects a too-short run of digits", "1234", nil)
checkID("accepts an 11 digit id", "98765432101", "98765432101")

print("")
print("throwaway identity")
let name = Identity.displayName()
check("display name is not empty", !name.isEmpty)
check("display name has two parts", name.split(separator: " ").count == 2)

var sawDifferent = false
for _ in 0..<10 where Identity.displayName() != name {
    sawDifferent = true
}
check("two display names are usually different", sawDifferent)

let alias = Identity.emailAlias(base: "someone@example.com")
check("alias keeps the mailbox", alias.hasPrefix("someone+"))
check("alias keeps the domain", alias.hasSuffix("@example.com"))
check("alias is tagged", alias.contains("+wtf"))
check("alias has exactly one at sign", alias.filter { $0 == "@" }.count == 1)

let bare = Identity.emailAlias(base: "someone")
check("a bare mailbox gets a default domain", bare.hasSuffix("@gmail.com"))
check("a bare mailbox is still tagged", bare.hasPrefix("someone+wtf"))

print("")
print("----------------------------------------")
print("passed: \(passed)   failed: \(failed)")
if failed > 0 {
    print("RESULT: FAILED")
    print("")
    exit(1)
}
print("RESULT: PASSED")
print("")
