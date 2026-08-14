package wtf.fix1132.android;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Turns whatever the user pasted into a Zoom web client link.
 *
 * The web client is the part that matters for 1132: it runs in the browser, so
 * it carries none of the native client's device identity. Feeding it a meeting
 * id directly is the most reliable bypass available on a phone.
 */
final class MeetingLink {

    /** Zoom meeting ids are 9 to 11 digits. */
    private static final Pattern MEETING_ID = Pattern.compile("(\\d[\\d\\s-]{7,20}\\d)");
    private static final Pattern PASSWORD = Pattern.compile("[?&]pwd=([^&\\s]+)");

    private MeetingLink() {
    }

    static final String JOIN_PAGE = "https://zoom.us/join";

    /**
     * @param input a meeting id, a zoom.us link, or a zoommtg:// link
     * @return a web client URL, or the generic join page when no id is found
     */
    static String toWebClientUrl(String input) {
        if (input == null) {
            return JOIN_PAGE;
        }
        String trimmed = input.trim();
        if (trimmed.isEmpty()) {
            return JOIN_PAGE;
        }

        String password = null;
        Matcher passwordMatch = PASSWORD.matcher(trimmed);
        if (passwordMatch.find()) {
            password = passwordMatch.group(1);
        }

        String id = extractMeetingId(trimmed);
        if (id == null) {
            // Not recognisable as a meeting, but if it is already a URL let the
            // browser deal with it rather than throwing it away.
            if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
                return trimmed;
            }
            return JOIN_PAGE;
        }

        StringBuilder url = new StringBuilder("https://zoom.us/wc/join/").append(id);
        if (password != null && !password.isEmpty()) {
            url.append("?pwd=").append(password);
        }
        return url.toString();
    }

    /** Pulls the digits of a meeting id out of free-form text. */
    static String extractMeetingId(String input) {
        if (input == null) {
            return null;
        }
        // A /j/<id> or /wc/join/<id> path segment is the most reliable signal,
        // so look for it before falling back to any run of digits.
        Matcher pathMatch = Pattern.compile("/(?:j|wc/join|s)/(\\d{9,11})").matcher(input);
        if (pathMatch.find()) {
            return pathMatch.group(1);
        }

        Matcher loose = MEETING_ID.matcher(input);
        while (loose.find()) {
            String digits = loose.group(1).replaceAll("[^0-9]", "");
            if (digits.length() >= 9 && digits.length() <= 11) {
                return digits;
            }
        }
        return null;
    }
}
