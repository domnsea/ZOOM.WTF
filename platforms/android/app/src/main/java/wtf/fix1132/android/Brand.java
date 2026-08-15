package wtf.fix1132.android;

import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * Palette and view builders for the 1132.WTF look.
 *
 * The whole interface is built in code rather than in layout XML, so the app
 * needs no AndroidX or Material dependency and stays a handful of small
 * framework-only classes.
 */
final class Brand {

    static final int BG = Color.parseColor("#0B0E14");
    static final int BG_TOP = Color.parseColor("#141A26");
    static final int BG_BOTTOM = Color.parseColor("#06080D");
    static final int INK = Color.parseColor("#F5F7FA");
    static final int MUTED = Color.parseColor("#8A94A6");
    static final int ACCENT = Color.parseColor("#00E5FF");
    static final int ACCENT2 = Color.parseColor("#FF2E88");
    static final int OK = Color.parseColor("#22C55E");
    static final int WARN = Color.parseColor("#FFB020");
    static final int ERR = Color.parseColor("#FF4D4D");

    private Brand() {
    }

    static int dp(Context context, float value) {
        return Math.round(TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, value, context.getResources().getDisplayMetrics()));
    }

    /** A rounded panel used for each section of the screen. */
    static LinearLayout card(Context context) {
        LinearLayout card = new LinearLayout(context);
        card.setOrientation(LinearLayout.VERTICAL);

        GradientDrawable background = new GradientDrawable();
        background.setColor(BG_TOP);
        background.setCornerRadius(dp(context, 16));
        background.setStroke(dp(context, 1), Color.parseColor("#22304A"));
        card.setBackground(background);

        int pad = dp(context, 18);
        card.setPadding(pad, pad, pad, pad);

        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        params.bottomMargin = dp(context, 14);
        card.setLayoutParams(params);
        return card;
    }

    /** Small all-caps label that opens a card, coloured to signal severity. */
    static TextView eyebrow(Context context, String text, int colour) {
        TextView view = new TextView(context);
        view.setText(text.toUpperCase());
        view.setTextColor(colour);
        view.setTextSize(11);
        view.setLetterSpacing(0.14f);
        view.setTypeface(view.getTypeface(), android.graphics.Typeface.BOLD);
        return view;
    }

    static TextView title(Context context, String text) {
        TextView view = new TextView(context);
        view.setText(text);
        view.setTextColor(INK);
        view.setTextSize(18);
        view.setTypeface(view.getTypeface(), android.graphics.Typeface.BOLD);
        view.setPadding(0, dp(context, 6), 0, 0);
        return view;
    }

    static TextView body(Context context, String text) {
        TextView view = new TextView(context);
        view.setText(text);
        view.setTextColor(MUTED);
        view.setTextSize(14);
        view.setLineSpacing(dp(context, 4), 1f);
        view.setPadding(0, dp(context, 8), 0, 0);
        return view;
    }

    /** Monospaced block used for status readouts. */
    static TextView mono(Context context, String text) {
        TextView view = new TextView(context);
        view.setText(text);
        view.setTextColor(INK);
        view.setTextSize(13);
        view.setTypeface(android.graphics.Typeface.MONOSPACE);
        view.setLineSpacing(dp(context, 3), 1f);

        GradientDrawable background = new GradientDrawable();
        background.setColor(BG_BOTTOM);
        background.setCornerRadius(dp(context, 10));
        view.setBackground(background);

        int pad = dp(context, 12);
        view.setPadding(pad, pad, pad, pad);

        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        params.topMargin = dp(context, 10);
        view.setLayoutParams(params);
        return view;
    }

    static Button button(Context context, String text, int accent, boolean filled) {
        Button button = new Button(context);
        button.setText(text);
        button.setAllCaps(false);
        button.setTextSize(15);
        button.setTypeface(button.getTypeface(), android.graphics.Typeface.BOLD);

        GradientDrawable background = new GradientDrawable();
        background.setCornerRadius(dp(context, 12));
        if (filled) {
            background.setColor(accent);
            button.setTextColor(BG_BOTTOM);
        } else {
            background.setColor(Color.TRANSPARENT);
            background.setStroke(dp(context, 2), accent);
            button.setTextColor(accent);
        }
        button.setBackground(background);
        button.setPadding(dp(context, 16), dp(context, 14), dp(context, 16), dp(context, 14));

        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        params.topMargin = dp(context, 12);
        button.setLayoutParams(params);
        return button;
    }

    /** Numbered badge that marks a card as level 1, 2, or 3. */
    static TextView levelBadge(Context context, String number, int colour) {
        TextView view = new TextView(context);
        view.setText(number);
        view.setTextColor(BG_BOTTOM);
        view.setTextSize(13);
        view.setGravity(Gravity.CENTER);
        view.setTypeface(view.getTypeface(), android.graphics.Typeface.BOLD);

        GradientDrawable background = new GradientDrawable();
        background.setShape(GradientDrawable.OVAL);
        background.setColor(colour);
        view.setBackground(background);

        int size = dp(context, 26);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(size, size);
        params.rightMargin = dp(context, 10);
        view.setLayoutParams(params);
        return view;
    }

    /** Horizontal strip holding a level badge next to its eyebrow label. */
    static LinearLayout levelHeader(Context context, String number, String label, int colour) {
        LinearLayout row = new LinearLayout(context);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(levelBadge(context, number, colour));
        row.addView(eyebrow(context, label, colour));
        return row;
    }

    static View spacer(Context context, int heightDp) {
        View view = new View(context);
        view.setLayoutParams(new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(context, heightDp)));
        return view;
    }
}
