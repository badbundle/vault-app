import SwiftUI

/// The app icon.
///
/// A full square; the system masks the corners. `VaultAppIconGenerator` renders
/// this at 1024 px into the asset catalog, so the icon on the Home Screen and the
/// door that spins in the in-app lock animation are one and the same drawing.
public struct VaultAppIconView: View {
    public var appearance: VaultAppIconAppearance

    public init(appearance: VaultAppIconAppearance = .light) {
        self.appearance = appearance
    }

    public var body: some View {
        ZStack {
            if appearance.hasOpaqueBackground {
                appearance.palette.background
            }
            VaultLockGlyphView(appearance: appearance)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview("Light") {
    VaultAppIconView(appearance: .light)
        .frame(width: 256, height: 256)
}

#Preview("Dark") {
    VaultAppIconView(appearance: .dark)
        .frame(width: 256, height: 256)
        .background(Color.black)
}

#Preview("Tinted") {
    VaultAppIconView(appearance: .tinted)
        .frame(width: 256, height: 256)
        .background(Color.black)
}
