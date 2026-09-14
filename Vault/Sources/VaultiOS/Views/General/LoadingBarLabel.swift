import Foundation
import SwiftUI

struct LoadingBarLabel: View {
    var text: String
    var body: some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .textCase(.uppercase)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .shadow(color: .black, radius: 10)
    }
}
