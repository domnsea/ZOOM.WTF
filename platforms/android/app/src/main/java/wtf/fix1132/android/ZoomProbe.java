package wtf.fix1132.android;

import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.net.Uri;
import android.os.Build;
import android.os.UserManager;

import java.util.List;

/**
 * What 1132.WTF can tell about Zoom on this device.
 *
 * Everything here is read-only. Android does not let one app clear another
 * app's data, so the app reports honestly and then hands the user straight to
 * the system screen that can.
 */
final class ZoomProbe {

    static final String ZOOM_PACKAGE = "us.zoom.videomeetings";

    final boolean zoomInstalled;
    final String zoomVersion;
    final boolean multiUserSupported;
    final boolean hasBrowser;

    private ZoomProbe(boolean zoomInstalled, String zoomVersion,
                      boolean multiUserSupported, boolean hasBrowser) {
        this.zoomInstalled = zoomInstalled;
        this.zoomVersion = zoomVersion;
        this.multiUserSupported = multiUserSupported;
        this.hasBrowser = hasBrowser;
    }

    static ZoomProbe inspect(Context context) {
        PackageManager packages = context.getPackageManager();

        boolean installed = false;
        String version = "";
        try {
            PackageInfo info = packages.getPackageInfo(ZOOM_PACKAGE, 0);
            installed = true;
            version = info.versionName == null ? "unknown" : info.versionName;
        } catch (PackageManager.NameNotFoundException absent) {
            // Either Zoom is not installed, or the manifest <queries> entry is
            // missing on Android 11+. The manifest declares it, so this means
            // it is genuinely absent.
            installed = false;
        }

        boolean multiUser = false;
        try {
            // Not every device allows extra users even when the API exists:
            // most phones do, many tablets do, some vendor builds do not.
            multiUser = UserManager.supportsMultipleUsers();
        } catch (Throwable ignored) {
            multiUser = false;
        }

        boolean browser = false;
        try {
            Intent probe = new Intent(Intent.ACTION_VIEW, Uri.parse("https://zoom.us/"));
            List<ResolveInfo> handlers = packages.queryIntentActivities(probe, 0);
            browser = handlers != null && !handlers.isEmpty();
        } catch (Throwable ignored) {
            browser = false;
        }

        return new ZoomProbe(installed, version, multiUser, browser);
    }

    /** The status readout shown at the top of the screen. */
    String describe() {
        StringBuilder text = new StringBuilder();
        text.append("Zoom app      ")
                .append(zoomInstalled ? "installed (" + zoomVersion + ")" : "not installed")
                .append('\n');
        text.append("Android       ").append(Build.VERSION.RELEASE)
                .append(" (API ").append(Build.VERSION.SDK_INT).append(")\n");
        text.append("Device        ").append(Build.MANUFACTURER).append(' ').append(Build.MODEL)
                .append('\n');
        text.append("Extra users   ").append(multiUserSupported ? "supported" : "not supported")
                .append('\n');
        text.append("Browser       ").append(hasBrowser ? "available" : "none found");
        return text.toString();
    }
}
