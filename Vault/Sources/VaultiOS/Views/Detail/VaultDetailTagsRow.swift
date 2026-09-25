import Foundation
import SwiftUI
import VaultFeed

/// The item editor's Tags row: its title and tag count, with the attached
/// tags beneath, lined up with the title.
///
/// Callers wrap it in the button that opens the tag picker, so the whole row,
/// pills included, is one tap target.
struct VaultDetailTagsRow: View {
    var tags: [VaultItemTag]
    /// How many tags are attached, as the row's value.
    var countDescription: String

    var body: some View {
        FormRow(
            image: Image(systemName: "tag"),
            color: .accentColor,
            style: .standard,
            alignment: .titleLine,
        ) {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Tags", value: countDescription)
                    .font(.body)
                    .alignmentGuide(.titleLine) { $0[VerticalAlignment.center] }

                if tags.isNotEmpty {
                    AttachedTagsView(tags: tags)
                        .padding(.bottom, 2)
                }
            }
        }
    }
}

extension VerticalAlignment {
    /// The middle of the row's title line. The icon centers on it, as it
    /// does beside the single-line rows around it, however many lines of
    /// tags follow.
    private enum TitleLine: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    fileprivate static let titleLine = VerticalAlignment(TitleLine.self)
}
