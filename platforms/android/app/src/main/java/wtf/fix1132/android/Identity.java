package wtf.fix1132.android;

import java.security.SecureRandom;

/**
 * Throwaway identity details for joining as somebody the host has not blocked.
 *
 * A display name is often all a manual host-side block was keyed on, so a fresh
 * one is worth trying before anything more drastic.
 */
final class Identity {

    private static final String[] FIRST = {
            "Alex", "Sam", "Jordan", "Casey", "Riley", "Quinn", "Avery", "Morgan",
            "Taylor", "Jamie", "Drew", "Reese", "Kai", "Rowan", "Sky", "Finn",
    };

    private static final String[] LAST = {
            "Chen", "Patel", "Garcia", "Kim", "Novak", "Silva", "Haddad", "Okafor",
            "Ivanov", "Dubois", "Rossi", "Nakamura", "Andersson", "Costa", "Weber",
    };

    private static final SecureRandom RANDOM = new SecureRandom();

    private Identity() {
    }

    static String displayName() {
        return FIRST[RANDOM.nextInt(FIRST.length)] + " " + LAST[RANDOM.nextInt(LAST.length)];
    }

    /**
     * A plus-address suggestion for making a new Zoom account on the same
     * mailbox. Most providers deliver anything after a "+" to the same inbox
     * while Zoom treats it as a different address.
     */
    static String emailAlias(String base) {
        String mailbox = base;
        String domain = "gmail.com";
        int at = base.indexOf('@');
        if (at > 0) {
            mailbox = base.substring(0, at);
            domain = base.substring(at + 1);
        }
        return mailbox + "+" + suffix() + "@" + domain;
    }

    private static String suffix() {
        // Short and unambiguous: no letters that read as digits.
        String alphabet = "abcdefghjkmnpqrstuvwxyz23456789";
        StringBuilder out = new StringBuilder("wtf");
        for (int i = 0; i < 4; i++) {
            out.append(alphabet.charAt(RANDOM.nextInt(alphabet.length())));
        }
        return out.toString();
    }
}
