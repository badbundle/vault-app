import SwiftUI

/// The app icon as the Mac shows it.
///
/// macOS doesn't mask an app's icon, so this draws `VaultAppIconView` in the Mac's rounded square, on the grid every
/// Mac app icon shares: an 824-point square with continuous corners, in the middle of a 1024-point canvas, with a soft
/// shadow below. `VaultAppIconGenerator` renders it at every size the Mac's asset catalog takes.
public struct VaultMacAppIconView: View {
    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let canvas = min(proxy.size.width, proxy.size.height)
            let unit = canvas / 1024
            VaultAppIconView(appearance: .light)
                .frame(width: 824 * unit, height: 824 * unit)
                .clipShape(RoundedRectangle(cornerRadius: 185.4 * unit, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 10 * unit, y: 10 * unit)
                .frame(width: canvas, height: canvas)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview("Mac") {
    VaultMacAppIconView()
        .frame(width: 256, height: 256)
}
