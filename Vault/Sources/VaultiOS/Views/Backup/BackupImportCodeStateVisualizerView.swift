import Foundation
import SwiftUI

/// A tile for each of a backup's QR codes, ticked off as it's scanned.
struct BackupImportCodeStateVisualizerView: View {
    var totalCount: Int
    var selectedIndexes: Set<Int>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LazyVGrid(columns: [.init(.adaptive(minimum: 30, maximum: 40))], spacing: 8) {
            ForEach(0 ..< totalCount, id: \.self) { index in
                tile(isScanned: selectedIndexes.contains(index))
            }
        }
    }

    /// The code's glyph, until it's scanned and a green tick replaces it with a bounce. With Reduce Motion, the tick
    /// fades in instead.
    private func tile(isScanned: Bool) -> some View {
        Image(systemName: isScanned ? "checkmark.circle.fill" : "qrcode")
            .font(.largeTitle)
            .foregroundStyle(isScanned ? Color.green : Color.primary)
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            .symbolEffect(.bounce, value: isScanned && !reduceMotion)
            .animation(reduceMotion ? .easeInOut(duration: 0.25) : .snappy, value: isScanned)
    }
}

#Preview {
    BackupImportCodeStateVisualizerView(totalCount: 20, selectedIndexes: [0, 5, 19])
}
