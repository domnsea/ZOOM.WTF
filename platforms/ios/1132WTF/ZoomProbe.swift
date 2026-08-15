import Foundation
import UIKit

/// What 1132.WTF can tell about Zoom on this iPhone.
///
/// iOS gives an app almost nothing about its neighbours. Whether Zoom is
/// installed can only be inferred by asking whether its URL scheme can be
/// opened, and that only works because the scheme is listed under
/// LSApplicationQueriesSchemes in the build settings.
struct ZoomProbe {
    let zoomInstalled: Bool
    let systemVersion: String
    let deviceModel: String

    static func inspect() -> ZoomProbe {
        var installed = false
        if let url = URL(string: "zoomus://") {
            installed = UIApplication.shared.canOpenURL(url)
        }
        return ZoomProbe(
            zoomInstalled: installed,
            systemVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model
        )
    }

    /// The status readout shown at the top of the screen.
    var readout: String {
        """
        Zoom app      \(zoomInstalled ? "installed" : "not detected")
        iOS           \(systemVersion)
        Device        \(deviceModel)
        Clean room    available
        """
    }
}
