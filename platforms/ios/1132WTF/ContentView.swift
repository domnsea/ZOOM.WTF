import SwiftUI
import UIKit

/// The 1132.WTF screen.
///
/// iOS sandboxing decides what this app can and cannot do, and the interface is
/// organised around that rather than around what would sound most impressive:
///
///   level 1  Only the system can remove another app's data, so the app spells
///            out the offload steps and opens Settings.
///   level 2  Impossible on iOS. There are no second user profiles, so the card
///            says so instead of pretending.
///   level 3  Fully implemented in-app, because the app owns its own web view
///            data store and can throw it away whenever it likes.
struct ContentView: View {
    @State private var probe = ZoomProbe.inspect()
    @State private var meetingInput = ""
    @State private var displayName = Identity.displayName()
    @State private var showCleanRoom = false
    @State private var showAliasPrompt = false
    @State private var emailBase = ""
    @State private var toast: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    statusCard
                    levelOneCard
                    levelTwoCard
                    levelThreeCard
                    troubleshootingCard
                    footer
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())

            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.bgBottom)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(Theme.accent)
                    )
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showCleanRoom) {
            CleanRoomView(url: MeetingLink.webClientURL(from: meetingInput))
        }
        .alert("New account email", isPresented: $showAliasPrompt) {
            TextField("you@gmail.com", text: $emailBase)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
            Button("Build it") {
                let base = emailBase.trimmingCharacters(in: .whitespaces)
                let alias = Identity.emailAlias(base: base.isEmpty ? "you@gmail.com" : base)
                UIPasteboard.general.string = alias
                show(toast: "Copied \(alias)")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Zoom treats a plus-address as a different account, while your mail "
                 + "provider still delivers it to the same inbox.")
        }
        .onAppear {
            // Re-probe on return: the user may have just reinstalled Zoom.
            probe = ZoomProbe.inspect()
        }
    }

    // ------------------------------------------------------------------ header

    private var header: some View {
        HStack(spacing: 14) {
            Image("AppLogo")
                .resizable()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("1132.WTF")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Theme.accent)
                Text("Zoom error 1132, fixed.")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.accent2)
            }
            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // ------------------------------------------------------------------ status

    private var statusCard: some View {
        Card {
            Eyebrow(text: "This iPhone")
            MonoBlock(text: probe.readout)
            if !probe.zoomInstalled {
                CardBody(
                    text: "Zoom was not detected here. Level 3 still works, because it joins "
                        + "through the web client instead of the app.",
                    colour: Theme.warn
                )
            }
        }
    }

    // ----------------------------------------------------------------- level 1

    private var levelOneCard: some View {
        Card {
            LevelHeader(number: "1", label: "Reset Zoom on this iPhone", colour: Theme.accent)
            CardTitle(text: "Offload and reinstall Zoom")
            CardBody(text: """
                Reinstalling Zoom throws away the device registration that error 1132 is \
                usually attached to.

                iOS does not let one app remove another app's data, so this has to be done \
                in Settings:

                1.  Settings, then General
                2.  iPhone Storage, then Zoom
                3.  Delete App, then confirm
                4.  Reinstall Zoom from the App Store
                5.  Join as a guest, without signing in

                Offload App is not enough on its own. It keeps the app's documents and data, \
                which is exactly the part that has to go.
                """)
            ActionButton(title: "Open Settings", colour: Theme.accent) {
                openSettings()
            }
        }
    }

    private func openSettings() {
        // iOS only permits deep links into this app's own settings page. From
        // there the user navigates to General, which is why the steps above are
        // spelled out rather than promised as a single tap.
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // ----------------------------------------------------------------- level 2

    private var levelTwoCard: some View {
        Card {
            LevelHeader(number: "2", label: "A second profile", colour: Theme.accent2)
            CardTitle(text: "Not possible on iOS")
            CardBody(text: """
                On Windows, macOS, and Linux, 1132.WTF can run Zoom as a throwaway operating \
                system user, which is the most reliable fix there is. iOS has no second user \
                profile and no way for one app to create one, so that level does not exist \
                here.

                The closest equivalents, in order of how well they work:

                •  Join from the clean room below, which needs nothing
                •  Use a different Zoom account, from a new email
                •  Borrow a second device on a different network
                """)
        }
    }

    // ----------------------------------------------------------------- level 3

    private var levelThreeCard: some View {
        Card {
            LevelHeader(number: "3", label: "Join without the app", colour: Theme.ok)
            CardTitle(text: "Clean room join")
            CardBody(text: "Zoom's web client carries none of the app's device identity. This "
                     + "runs inside 1132.WTF in a session with no cookies and no storage, "
                     + "thrown away the moment you close it.")

            TextField("Meeting link or ID", text: $meetingInput)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundColor(Theme.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.bgBottom)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.muted, lineWidth: 1)
                )

            MonoBlock(text: "Display name:  \(displayName)")

            ActionButton(title: "Join in a wiped session", colour: Theme.ok) {
                showCleanRoom = true
            }
            ActionButton(title: "Open in Safari instead", colour: Theme.ok, filled: false) {
                openInSafari()
            }
            ActionButton(title: "New display name", colour: Theme.muted, filled: false) {
                displayName = Identity.displayName()
                UIPasteboard.general.string = displayName
                show(toast: "Copied \(displayName)")
            }
            ActionButton(title: "Suggest a new account email", colour: Theme.muted, filled: false) {
                showAliasPrompt = true
            }
        }
    }

    private func openInSafari() {
        let target = MeetingLink.webClientURL(from: meetingInput)
        guard let url = URL(string: target) else { return }
        UIApplication.shared.open(url)
        // No app can force Safari into private browsing, so say so rather than
        // letting the user assume it happened.
        show(toast: "Use a Private tab in Safari for a clean session")
    }

    // -------------------------------------------------------- troubleshooting

    private var troubleshootingCard: some View {
        Card {
            Eyebrow(text: "When none of it works", colour: Theme.warn)
            CardBody(text: """
                1132 is not always on your phone. Reading it correctly saves a lot of time.

                Comes back instantly, even after reinstalling
                     The block is on your Zoom account, on Zoom's servers. Make a new \
                account, or join as a guest without signing in.

                Nothing on this iPhone works, but a laptop can join
                     The block is on your IP address. Try mobile data instead of Wi-Fi, or \
                the other way round.

                The host removed you by name
                     Join with a different display name. The button above generates one.

                No app on your iPhone can undo a block that lives on Zoom's servers. When \
                that is what is happening, the levels above cannot help, and nothing that \
                claims otherwise is telling you the truth.
                """)
        }
    }

    private var footer: some View {
        Text("1132.WTF  v1.0.0")
            .font(.system(size: 11))
            .foregroundColor(Theme.muted)
            .padding(.top, 6)
    }

    // ----------------------------------------------------------------- helpers

    private func show(toast message: String) {
        withAnimation {
            toast = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation {
                if toast == message { toast = nil }
            }
        }
    }
}

#Preview {
    ContentView()
}
