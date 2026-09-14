import Foundation
import SwiftUI

struct FormRow<Content: View>: View {
    var image: Image
    var color: Color
    var style: Style
    var alignment: VerticalAlignment
    var content: () -> Content

    @ScaledMetric(relativeTo: .body) private var prominentIconSize: Double = 28

    enum Style {
        case prominent
        case standard
    }

    init(
        image: Image,
        color: Color,
        style: Style = .prominent,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.image = image
        self.color = color
        self.style = style
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 16) {
            switch style {
            case .prominent:
                prominentIcon
            case .standard:
                standardIcon
            }
            content()
        }
    }

    private var prominentIcon: some View {
        ZStack {
            color
            image
                .font(.body)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(width: prominentIconSize, height: prominentIconSize)
        .foregroundStyle(.white)
    }

    private var standardIcon: some View {
        image
            .frame(width: prominentIconSize, height: prominentIconSize)
            .foregroundStyle(color)
    }
}

#Preview {
    List {
        FormRow(image: Image(systemName: "checkmark"), color: .accentColor, style: .standard) {
            Text("Hello")
        }
        FormRow(image: Image(systemName: "checkmark"), color: .accentColor) {
            Text("Hello Again")
        }
        FormRow(image: Image(systemName: "checkmark"), color: .accentColor, style: .prominent) {
            TextAndSubtitle(title: "Hello", subtitle: "world\nwe\ngood")
        }
        FormRow(
            image: Image(systemName: "checkmark"),
            color: .accentColor,
            style: .prominent,
            alignment: .firstTextBaseline,
        ) {
            TextAndSubtitle(title: "Hello", subtitle: "world\nwe\ngood")
        }
    }
}
