package wtf.fix1132.android;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

/**
 * The 1132.WTF screen.
 *
 * Android sandboxing decides what this app can and cannot do, and the interface
 * is organised around that rather than around what would sound most impressive:
 *
 *   level 1  Zoom's own data can only be cleared by the system, so the app
 *            takes the user straight to that screen with the steps spelled out.
 *   level 2  A second Android user profile is the phone equivalent of a
 *            throwaway desktop account, so the app deep-links there too.
 *   level 3  Fully implemented in-app, because the app owns its own WebView
 *            cookie jar and can wipe it whenever it likes.
 */
public class MainActivity extends Activity {

    private ZoomProbe probe;
    private TextView statusReadout;
    private EditText meetingInput;
    private TextView generatedName;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(buildScreen());
    }

    @Override
    protected void onResume() {
        super.onResume();
        // Re-probe on return: the user may have just cleared Zoom's data or
        // added a profile in Settings, and the readout should reflect that.
        refreshStatus();
    }

    private View buildScreen() {
        probe = ZoomProbe.inspect(this);

        ScrollView scroller = new ScrollView(this);
        scroller.setBackgroundColor(Brand.BG);
        scroller.setFillViewport(true);

        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        int pad = Brand.dp(this, 16);
        column.setPadding(pad, pad, pad, Brand.dp(this, 28));
        scroller.addView(column);

        column.addView(buildHeader());
        column.addView(buildStatusCard());
        column.addView(buildLevelOneCard());
        column.addView(buildLevelTwoCard());
        column.addView(buildLevelThreeCard());
        column.addView(buildTroubleshootingCard());
        column.addView(buildFooter());

        return scroller;
    }

    // ------------------------------------------------------------------ header

    private View buildHeader() {
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(Brand.dp(this, 4), Brand.dp(this, 10), 0, Brand.dp(this, 18));

        ImageView logo = new ImageView(this);
        logo.setImageResource(R.mipmap.ic_launcher);
        int size = Brand.dp(this, 54);
        LinearLayout.LayoutParams logoParams = new LinearLayout.LayoutParams(size, size);
        logoParams.rightMargin = Brand.dp(this, 14);
        logo.setLayoutParams(logoParams);
        header.addView(logo);

        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);

        TextView name = new TextView(this);
        name.setText("1132.WTF");
        name.setTextColor(Brand.ACCENT);
        name.setTextSize(26);
        name.setTypeface(name.getTypeface(), Typeface.BOLD);
        text.addView(name);

        TextView tagline = new TextView(this);
        tagline.setText(getString(R.string.tagline));
        tagline.setTextColor(Brand.ACCENT2);
        tagline.setTextSize(13);
        tagline.setTypeface(tagline.getTypeface(), Typeface.BOLD);
        text.addView(tagline);

        header.addView(text);
        return header;
    }

    // ------------------------------------------------------------------ status

    private View buildStatusCard() {
        LinearLayout card = Brand.card(this);
        card.addView(Brand.eyebrow(this, "This phone", Brand.MUTED));
        statusReadout = Brand.mono(this, probe.describe());
        card.addView(statusReadout);

        if (!probe.zoomInstalled) {
            TextView note = Brand.body(this,
                    "Zoom is not installed here. Level 3 still works, because it "
                            + "joins through the browser instead of the app.");
            note.setTextColor(Brand.WARN);
            card.addView(note);
        }
        return card;
    }

    private void refreshStatus() {
        probe = ZoomProbe.inspect(this);
        if (statusReadout != null) {
            statusReadout.setText(probe.describe());
        }
    }

    // ----------------------------------------------------------------- level 1

    private View buildLevelOneCard() {
        LinearLayout card = Brand.card(this);
        card.addView(Brand.levelHeader(this, "1", "STEP 1 - Clear Zoom", Brand.ACCENT));
        card.addView(Brand.title(this, "STEP 1 - Tap the button below"));
        card.addView(Brand.body(this,
                "STEP 2 - On the next screen:\n"
                        + "Force stop  →  Storage  →  Clear storage\n\n"
                        + "LAUNCH - Open Zoom. Join as a guest.\n"
                        + "Do not sign in as the old account."));

        Button open = Brand.button(this, "STEP 1 - Open Zoom settings", Brand.ACCENT, true);
        open.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                openZoomSettings();
            }
        });
        card.addView(open);

        if (!probe.zoomInstalled) {
            open.setEnabled(false);
            open.setAlpha(0.4f);
        }
        return card;
    }

    private void openZoomSettings() {
        Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
        intent.setData(Uri.parse("package:" + ZoomProbe.ZOOM_PACKAGE));
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            startActivity(intent);
        } catch (ActivityNotFoundException notFound) {
            // Fall back to the full app list, which every build has.
            try {
                startActivity(new Intent(Settings.ACTION_APPLICATION_SETTINGS));
                toast("Find Zoom in this list, then Storage, then Clear storage.");
            } catch (ActivityNotFoundException stillNotFound) {
                toast("Could not open Settings on this device.");
            }
        }
    }

    // ----------------------------------------------------------------- level 2

    private View buildLevelTwoCard() {
        LinearLayout card = Brand.card(this);
        card.addView(Brand.levelHeader(this, "2", "STEP 2 - New phone user", Brand.ACCENT2));
        card.addView(Brand.title(this, "Only if STEP 1 still fails"));

        String explanation = probe.multiUserSupported
                ? "STEP 1 - Tap the button. Add a user. Switch to it.\n\n"
                + "STEP 2 - Install Zoom on that user.\n\n"
                + "LAUNCH - Join as a guest. Do not sign in as the old account."
                : "This phone cannot add users. Skip this.\n\n"
                + "Go to STEP 3 instead.";

        card.addView(Brand.body(this, explanation));

        Button open = Brand.button(this, "STEP 2 - Open user settings", Brand.ACCENT2, false);
        open.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                openUserSettings();
            }
        });
        if (!probe.multiUserSupported) {
            open.setEnabled(false);
            open.setAlpha(0.4f);
        }
        card.addView(open);
        return card;
    }

    private void openUserSettings() {
        // There is no public constant for the user settings screen, so try the
        // documented action string first and fall back to top-level Settings.
        try {
            Intent intent = new Intent("android.settings.USER_SETTINGS");
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
            return;
        } catch (ActivityNotFoundException ignored) {
            // Handled below.
        }
        try {
            startActivity(new Intent(Settings.ACTION_SETTINGS));
            toast("Look under System, then Multiple users.");
        } catch (ActivityNotFoundException notFound) {
            toast("Could not open Settings on this device.");
        }
    }

    // ----------------------------------------------------------------- level 3

    private View buildLevelThreeCard() {
        LinearLayout card = Brand.card(this);
        card.addView(Brand.levelHeader(this, "3", "STEP 3 - Join in browser", Brand.OK));
        card.addView(Brand.title(this, "Only if STEP 1 and STEP 2 still fail"));
        card.addView(Brand.body(this,
                "STEP 1 - Type the meeting number below.\n"
                        + "STEP 2 - Use the name shown (not your old name).\n"
                        + "LAUNCH"));

        meetingInput = new EditText(this);
        meetingInput.setHint("STEP 1 - Meeting number or link");
        meetingInput.setHintTextColor(Brand.MUTED);
        meetingInput.setTextColor(Brand.INK);
        meetingInput.setTextSize(15);
        meetingInput.setSingleLine(true);
        GradientDrawable inputBackground = new GradientDrawable();
        inputBackground.setColor(Brand.BG_BOTTOM);
        inputBackground.setCornerRadius(Brand.dp(this, 10));
        inputBackground.setStroke(Brand.dp(this, 1), Brand.MUTED);
        meetingInput.setBackground(inputBackground);
        int inputPad = Brand.dp(this, 14);
        meetingInput.setPadding(inputPad, inputPad, inputPad, inputPad);
        LinearLayout.LayoutParams inputParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        inputParams.topMargin = Brand.dp(this, 14);
        meetingInput.setLayoutParams(inputParams);
        card.addView(meetingInput);

        generatedName = Brand.mono(this, "Display name:  " + Identity.displayName());
        card.addView(generatedName);

        Button cleanRoom = Brand.button(this, "LAUNCH", Brand.OK, true);
        cleanRoom.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                launchCleanRoom();
            }
        });
        card.addView(cleanRoom);

        Button browser = Brand.button(this, "Open in my browser instead", Brand.OK, false);
        browser.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                openInBrowser();
            }
        });
        card.addView(browser);

        Button newName = Brand.button(this, "New display name", Brand.MUTED, false);
        newName.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                String name = Identity.displayName();
                generatedName.setText("Display name:  " + name);
                copyToClipboard("Display name", name);
            }
        });
        card.addView(newName);

        Button alias = Brand.button(this, "Suggest a new account email", Brand.MUTED, false);
        alias.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                askForEmailBase();
            }
        });
        card.addView(alias);

        return card;
    }

    private String currentUrl() {
        String typed = meetingInput == null ? "" : meetingInput.getText().toString();
        return MeetingLink.toWebClientUrl(typed);
    }

    private void launchCleanRoom() {
        Intent intent = new Intent(this, CleanRoomActivity.class);
        intent.putExtra(CleanRoomActivity.EXTRA_URL, currentUrl());
        startActivity(intent);
    }

    private void openInBrowser() {
        String url = currentUrl();
        Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
        // Chrome honours this on many builds and opens an incognito tab. When it
        // does not, the tab opens normally, which is why the dialog below still
        // tells the user to use a private tab.
        intent.putExtra("com.android.browser.application_id", getPackageName());
        intent.putExtra("com.google.android.apps.chrome.EXTRA_OPEN_NEW_INCOGNITO_TAB", true);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            startActivity(intent);
            toast("If it did not open privately, use your browser's private tab.");
        } catch (ActivityNotFoundException notFound) {
            toast("No browser is installed on this device.");
        }
    }

    private void askForEmailBase() {
        final EditText input = new EditText(this);
        input.setHint("you@gmail.com");
        input.setSingleLine(true);

        new AlertDialog.Builder(this)
                .setTitle("New account email")
                .setMessage("Zoom treats a plus-address as a different account, while your "
                        + "mail provider still delivers it to the same inbox. Enter your "
                        + "address and 1132.WTF will build one.")
                .setView(input)
                .setPositiveButton("Build it", (dialog, which) -> {
                    String base = input.getText().toString().trim();
                    if (base.isEmpty()) {
                        base = "you@gmail.com";
                    }
                    String alias = Identity.emailAlias(base);
                    copyToClipboard("Email alias", alias);
                    new AlertDialog.Builder(MainActivity.this)
                            .setTitle("Copied")
                            .setMessage(alias
                                    + "\n\nSign up for a new Zoom account with this, then join "
                                    + "the meeting with it.")
                            .setPositiveButton("Done", null)
                            .show();
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    // -------------------------------------------------------- troubleshooting

    private View buildTroubleshootingCard() {
        LinearLayout card = Brand.card(this);
        card.addView(Brand.eyebrow(this, "When none of it works", Brand.WARN));
        card.addView(Brand.body(this,
                "1132 is not always on your phone. Reading it correctly saves a lot of time.\n\n"
                        + "Comes back instantly, even in a fresh profile\n"
                        + "     The block is on your Zoom account, on Zoom's servers. Make a "
                        + "new account, or join as a guest without signing in.\n\n"
                        + "Nothing on this phone works, but a laptop can join\n"
                        + "     The block is on your IP address. Try mobile data instead of "
                        + "Wi-Fi, or the other way round.\n\n"
                        + "The host removed you by name\n"
                        + "     Join with a different display name. The button above generates "
                        + "one.\n\n"
                        + "No app on your phone can undo a block that lives on Zoom's servers. "
                        + "When that is what is happening, the levels above cannot help, and "
                        + "nothing that claims otherwise is telling you the truth."));
        return card;
    }

    private View buildFooter() {
        TextView footer = new TextView(this);
        footer.setText("1132.WTF  v1.0.0");
        footer.setTextColor(Brand.MUTED);
        footer.setTextSize(11);
        footer.setGravity(Gravity.CENTER);
        footer.setPadding(0, Brand.dp(this, 10), 0, 0);
        return footer;
    }

    // ------------------------------------------------------------------ helpers

    private void copyToClipboard(String label, String value) {
        ClipboardManager clipboard =
                (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        if (clipboard != null) {
            clipboard.setPrimaryClip(ClipData.newPlainText(label, value));
            toast(label + " copied: " + value);
        }
    }

    private void toast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show();
    }
}
