import Foundation
import SwiftUI

/// Stands in for a page's Authenticate button on a device with no passcode, Face ID or Touch ID, where there's
/// nothing to authenticate with. The page stays locked until one is set up.
struct PasscodeRequiredSection: View {
    /// What the passcode is needed for, as "Set up a passcode on this device to …".
    var message: String

    var body: some View {
        Section {
            FormRow(image: Image(systemName: "lock.trianglebadge.exclamationmark.fill"), color: .red) {
                TextAndSubtitle(title: "Passcode Required", subtitle: message)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
