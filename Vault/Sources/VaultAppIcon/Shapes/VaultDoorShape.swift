import SwiftUI

/// The safe door: a rounded square frame, open in the middle.
public struct VaultDoorShape: Shape {
    public var metrics: VaultIconMetrics

    public init(metrics: VaultIconMetrics = .standard) {
        self.metrics = metrics
    }

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let doorSide = metrics.doorSide * side
        let stroke = metrics.doorStroke * side
        let radius = metrics.doorCornerRadius * side
        let outer = CGRect(
            x: rect.midX - doorSide / 2,
            y: rect.midY - doorSide / 2,
            width: doorSide,
            height: doorSide,
        )
        let inner = outer.insetBy(dx: stroke, dy: stroke)
        let outerPath = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: outer)
        let innerPath = RoundedRectangle(cornerRadius: max(radius - stroke, 0), style: .continuous).path(in: inner)
        return outerPath.subtracting(innerPath)
    }
}
