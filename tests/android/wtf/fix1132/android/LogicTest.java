package wtf.fix1132.android;

/**
 * Tests for the parts of the Android app that use no Android APIs.
 *
 * MeetingLink and Identity are plain Java, so they can be compiled and run on
 * any JDK without an emulator. That matters because meeting link parsing is the
 * fiddliest logic in the app and the easiest to get quietly wrong.
 *
 * Run through tests/test_android_logic.sh.
 */
public final class LogicTest {

    private static int passed = 0;
    private static int failed = 0;

    public static void main(String[] args) {
        System.out.println();
        System.out.println("1132.WTF Android logic tests");
        System.out.println();

        System.out.println("meeting link to web client URL");
        checkUrl("a bare meeting id", "1234567890",
                "https://zoom.us/wc/join/1234567890");
        checkUrl("an id written with spaces", "123 4567 890",
                "https://zoom.us/wc/join/1234567890");
        checkUrl("an id written with dashes", "123-4567-890",
                "https://zoom.us/wc/join/1234567890");
        checkUrl("a standard join link", "https://zoom.us/j/1234567890",
                "https://zoom.us/wc/join/1234567890");
        checkUrl("a regional join link", "https://us02web.zoom.us/j/98765432101",
                "https://zoom.us/wc/join/98765432101");
        checkUrl("a link with a password", "https://zoom.us/j/1234567890?pwd=AbC123",
                "https://zoom.us/wc/join/1234567890?pwd=AbC123");
        checkUrl("a zoommtg deep link", "zoommtg://zoom.us/join?confno=1234567890",
                "https://zoom.us/wc/join/1234567890");
        checkUrl("a web client link already", "https://zoom.us/wc/join/1234567890",
                "https://zoom.us/wc/join/1234567890");
        checkUrl("surrounding whitespace", "  1234567890  ",
                "https://zoom.us/wc/join/1234567890");

        System.out.println();
        System.out.println("input that is not a meeting");
        checkUrl("empty input falls back to the join page", "",
                MeetingLink.JOIN_PAGE);
        checkUrl("null input falls back to the join page", null,
                MeetingLink.JOIN_PAGE);
        checkUrl("words fall back to the join page", "hello there",
                MeetingLink.JOIN_PAGE);
        checkUrl("too few digits falls back to the join page", "12345",
                MeetingLink.JOIN_PAGE);
        checkUrl("an unrelated URL is passed through", "https://example.com/foo",
                "https://example.com/foo");

        System.out.println();
        System.out.println("meeting id extraction");
        checkId("finds an id in a sentence", "join 1234567890 please", "1234567890");
        checkId("prefers the path segment", "https://zoom.us/j/1234567890", "1234567890");
        checkId("returns null when absent", "no numbers here", null);
        checkId("rejects a too-short run of digits", "1234", null);
        checkId("accepts an 11 digit id", "98765432101", "98765432101");

        System.out.println();
        System.out.println("throwaway identity");
        String name = Identity.displayName();
        check("display name is not empty", name != null && !name.isEmpty());
        check("display name has two parts", name.split(" ").length == 2);
        check("two display names are usually different", differentWithinTenTries());

        String alias = Identity.emailAlias("someone@example.com");
        check("alias keeps the mailbox", alias.startsWith("someone+"));
        check("alias keeps the domain", alias.endsWith("@example.com"));
        check("alias is tagged", alias.contains("+wtf"));
        check("alias has exactly one at sign", alias.indexOf('@') == alias.lastIndexOf('@'));

        String bare = Identity.emailAlias("someone");
        check("a bare mailbox gets a default domain", bare.endsWith("@gmail.com"));
        check("a bare mailbox is still tagged", bare.startsWith("someone+wtf"));

        System.out.println();
        System.out.println("----------------------------------------");
        System.out.printf("passed: %d   failed: %d%n", passed, failed);
        if (failed > 0) {
            System.out.println("RESULT: FAILED");
            System.out.println();
            System.exit(1);
        }
        System.out.println("RESULT: PASSED");
        System.out.println();
    }

    private static boolean differentWithinTenTries() {
        String first = Identity.displayName();
        for (int i = 0; i < 10; i++) {
            if (!Identity.displayName().equals(first)) {
                return true;
            }
        }
        return false;
    }

    private static void checkUrl(String description, String input, String expected) {
        String actual = MeetingLink.toWebClientUrl(input);
        if (expected.equals(actual)) {
            pass(description);
        } else {
            fail(description, "expected " + expected + " but got " + actual);
        }
    }

    private static void checkId(String description, String input, String expected) {
        String actual = MeetingLink.extractMeetingId(input);
        boolean same = expected == null ? actual == null : expected.equals(actual);
        if (same) {
            pass(description);
        } else {
            fail(description, "expected " + expected + " but got " + actual);
        }
    }

    private static void check(String description, boolean condition) {
        if (condition) {
            pass(description);
        } else {
            fail(description, "condition was false");
        }
    }

    private static void pass(String description) {
        passed++;
        System.out.println("  ok    " + description);
    }

    private static void fail(String description, String detail) {
        failed++;
        System.out.println("  FAIL  " + description);
        System.out.println("        " + detail);
    }
}
