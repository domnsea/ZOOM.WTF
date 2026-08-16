package wtf.fix1132.android;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebStorage;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

/**
 * Level 3, implemented properly.
 *
 * Zoom's web client runs in a WebView whose cookie jar and storage belong to
 * this app, which means 1132.WTF can genuinely erase the session itself rather
 * than asking the user to trust that a browser did. Every entry into this
 * screen starts from an empty jar.
 */
public class CleanRoomActivity extends Activity {

    static final String EXTRA_URL = "wtf.fix1132.android.URL";
    private static final int PERMISSION_REQUEST = 4711;

    private WebView web;
    private ProgressBar progress;
    private TextView banner;
    private String url;
    private PermissionRequest pendingRequest;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        url = getIntent().getStringExtra(EXTRA_URL);
        if (url == null || url.isEmpty()) {
            url = MeetingLink.JOIN_PAGE;
        }

        setContentView(buildScreen());
        requestMediaPermissions();
        wipeAndLoad();
    }

    private View buildScreen() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Brand.BG);

        banner = new TextView(this);
        banner.setText("Fresh session - no cookies, no history, no device id");
        banner.setTextColor(Brand.OK);
        banner.setTextSize(12);
        banner.setTypeface(banner.getTypeface(), Typeface.BOLD);
        int pad = Brand.dp(this, 12);
        banner.setPadding(pad, pad, pad, Brand.dp(this, 8));
        root.addView(banner);

        progress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        progress.setMax(100);
        progress.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, Brand.dp(this, 3)));
        root.addView(progress);

        web = new WebView(this);
        web.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        configureWebView();
        root.addView(web);

        LinearLayout controls = new LinearLayout(this);
        controls.setOrientation(LinearLayout.HORIZONTAL);
        controls.setPadding(pad, Brand.dp(this, 6), pad, pad);

        Button wipe = Brand.button(this, "Wipe and reload", Brand.ACCENT, false);
        LinearLayout.LayoutParams half = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        half.rightMargin = Brand.dp(this, 6);
        half.topMargin = 0;
        wipe.setLayoutParams(half);
        wipe.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                wipeAndLoad();
                Toast.makeText(CleanRoomActivity.this,
                        "Session wiped. Loading again.", Toast.LENGTH_SHORT).show();
            }
        });
        controls.addView(wipe);

        Button external = Brand.button(this, "Open in browser", Brand.MUTED, false);
        LinearLayout.LayoutParams otherHalf = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        otherHalf.leftMargin = Brand.dp(this, 6);
        otherHalf.topMargin = 0;
        external.setLayoutParams(otherHalf);
        external.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                try {
                    startActivity(intent);
                } catch (Exception failed) {
                    Toast.makeText(CleanRoomActivity.this,
                            "No browser is installed.", Toast.LENGTH_LONG).show();
                }
            }
        });
        controls.addView(external);

        root.addView(controls);
        return root;
    }

    private void configureWebView() {
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        settings.setBuiltInZoomControls(true);
        settings.setDisplayZoomControls(false);
        // Zoom's web client checks the user agent and refuses unknown browsers,
        // so present as the Chrome build that WebView is actually based on.
        settings.setUserAgentString(settings.getUserAgentString()
                .replace("; wv", "")
                .replace("Version/4.0 ", ""));

        web.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String finishedUrl) {
                progress.setVisibility(View.GONE);
            }
        });

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                progress.setVisibility(newProgress >= 100 ? View.GONE : View.VISIBLE);
                progress.setProgress(newProgress);
            }

            @Override
            public void onPermissionRequest(final PermissionRequest request) {
                // The meeting needs camera and microphone. Only grant what the
                // user has already allowed the app itself to use.
                if (hasMediaPermissions()) {
                    request.grant(request.getResources());
                } else {
                    pendingRequest = request;
                    requestMediaPermissions();
                }
            }
        });
    }

    /** Empties every store this WebView owns, then loads the meeting. */
    @SuppressWarnings("deprecation") // removeAllCookie is the only option below API 21.
    private void wipeAndLoad() {
        CookieManager cookies = CookieManager.getInstance();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            cookies.removeAllCookies(null);
            cookies.flush();
        } else {
            cookies.removeAllCookie();
        }
        cookies.setAcceptCookie(true);

        WebStorage.getInstance().deleteAllData();
        web.clearCache(true);
        web.clearHistory();
        web.clearFormData();

        progress.setVisibility(View.VISIBLE);
        progress.setProgress(0);
        web.loadUrl(url);
    }

    private boolean hasMediaPermissions() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true;
        }
        return checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
                && checkSelfPermission(Manifest.permission.RECORD_AUDIO)
                == PackageManager.PERMISSION_GRANTED;
    }

    private void requestMediaPermissions() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || hasMediaPermissions()) {
            return;
        }
        requestPermissions(
                new String[]{Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO},
                PERMISSION_REQUEST);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        if (requestCode != PERMISSION_REQUEST) {
            return;
        }
        if (pendingRequest != null) {
            if (hasMediaPermissions()) {
                pendingRequest.grant(pendingRequest.getResources());
            } else {
                pendingRequest.deny();
                banner.setText("Camera and microphone denied - you can still join to listen");
                banner.setTextColor(Brand.WARN);
            }
            pendingRequest = null;
        }
    }

    // Deprecated from API 33, but the replacement lives in AndroidX and this app
    // deliberately has no dependencies. Still called on every supported version.
    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        if (web != null && web.canGoBack()) {
            web.goBack();
            return;
        }
        super.onBackPressed();
    }

    @Override
    @SuppressWarnings("deprecation") // removeAllCookie is the only option below API 21.
    protected void onDestroy() {
        // Leave nothing behind for the next session to inherit.
        if (web != null) {
            web.stopLoading();
            web.clearCache(true);
            web.clearHistory();
            web.destroy();
            web = null;
        }
        CookieManager cookies = CookieManager.getInstance();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            cookies.removeAllCookies(null);
            cookies.flush();
        } else {
            cookies.removeAllCookie();
        }
        WebStorage.getInstance().deleteAllData();
        super.onDestroy();
    }
}
