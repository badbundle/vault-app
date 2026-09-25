import Foundation
import SwiftUI
import VaultFeed

/// A text field whose label stays visible once something has been entered.
///
/// A plain `TextField` only shows its placeholder while it's empty, so once there's a value it's no longer clear what
/// the field was asking for. Here the label rests in the field like a placeholder while it's empty, then floats above
/// the value as soon as the field is focused or filled. The floating label is tinted while the field is focused and
/// turns red when the value has an error, with the error's message under the value.
///
/// Made for a `Form` row, so it draws no background of its own. Text input modifiers such as `keyboardType(_:)`,
/// `textInputAutocapitalization(_:)`, `submitLabel(_:)`, `onSubmit(of:_:)` and `focused(_:equals:)` apply to it just
/// as they would to a `TextField`.
struct LabeledTextField: View {
    enum Kind {
        /// A single line of text.
        case plain
        /// A single line of text that's masked as it's typed.
        ///
        /// With `isRevealed`, a button beside the field shows and hides the text. The caller owns the binding, so it
        /// can hide the text again whenever it needs to (like when the app goes into the background).
        case secure(isRevealed: Binding<Bool>? = nil)
        /// Text over any number of lines, where Return starts a new line. Always at least `minLines` tall, and grows
        /// with the text.
        case multiline(minLines: Int)
    }

    /// What the field reports about its current value.
    enum Status: Equatable {
        /// Nothing to report.
        case none
        /// The value has been checked and is good, like a password confirmation that matches.
        case valid
        /// The value can't be used as it is, optionally with a message explaining why.
        case error(message: String? = nil)
    }

    private var title: String
    @Binding private var text: String
    private var prompt: String?
    private var kind: Kind
    private var status: Status

    @FocusState private var isFocused: Bool
    @State private var floatingLabelHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - title: Names what the field is for. Always visible, and read by VoiceOver.
    ///   - prompt: An example of what to enter, shown while the field is focused and empty.
    init(
        _ title: String,
        text: Binding<String>,
        prompt: String? = nil,
        kind: Kind = .plain,
        status: Status = .none,
    ) {
        self.title = title
        _text = text
        self.prompt = prompt
        self.kind = kind
        self.status = status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                labeledInput
                accessories
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: isLabelFloating)
        .animation(.snappy, value: status)
    }

    // MARK: - Label

    /// The label floats above the value whenever there's a value, or one is being typed.
    private var isLabelFloating: Bool {
        isFocused || text.isNotEmpty
    }

    private static let floatingLabelFont = Font.footnote.weight(.medium)
    private static let floatingLabelSpacing: CGFloat = 2

    /// The input, with a line reserved above it for the floating label.
    ///
    /// The line is always reserved, so the field doesn't change height as the label moves.
    private var labeledInput: some View {
        VStack(alignment: .leading, spacing: Self.floatingLabelSpacing) {
            Text(title)
                .font(Self.floatingLabelFont)
                .lineLimit(1)
                .hidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    floatingLabelHeight = height
                }
                // The reserved line is part of the field, so tapping it starts editing too.
                .contentShape(.rect)
                .onTapGesture {
                    isFocused = true
                }

            input
                .accessibilityHint(prompt ?? "")
                .overlay(alignment: restsLabelOnFirstLine ? .topLeading : .leading) {
                    promptOverlay
                }
        }
        .overlay(alignment: .topLeading) {
            label
        }
    }

    /// A single label that moves and resizes between resting in the field and floating above it.
    private var label: some View {
        Text(title)
            .font(isLabelFloating ? Self.floatingLabelFont : .body)
            // The label is never styled like the value, even when the value is monospaced.
            .fontDesign(nil)
            .foregroundStyle(labelColor)
            .lineLimit(1)
            .contentTransition(.interpolate)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: labelAlignment)
            .offset(y: labelOffset)
            .allowsHitTesting(false)
            // The input already carries the title as its accessibility label.
            .accessibilityHidden(true)
    }

    private var labelColor: Color {
        switch status {
        case .error: .red
        case .none, .valid: isFocused ? .accentColor : .secondary
        }
    }

    /// A field that's taller than one line rests its label on the first line, where the text will start.
    /// A single line field centers it, so it reads like a regular placeholder.
    private var labelAlignment: Alignment {
        isLabelFloating || restsLabelOnFirstLine ? .topLeading : .leading
    }

    private var labelOffset: CGFloat {
        isLabelFloating || !restsLabelOnFirstLine ? 0 : floatingLabelHeight + Self.floatingLabelSpacing
    }

    private var restsLabelOnFirstLine: Bool {
        if case let .multiline(minLines) = kind {
            minLines > 1
        } else {
            false
        }
    }

    // MARK: - Input

    @ViewBuilder
    private var input: some View {
        switch kind {
        case .plain:
            textField(axis: .horizontal)
        case let .secure(isRevealed):
            ZStack(alignment: .leading) {
                // A secure field is a little shorter than a plain one, so this keeps the field the same height as
                // its text is shown and hidden.
                TextField(text: .constant("")) {
                    EmptyView()
                }
                .hidden()

                if isRevealed?.wrappedValue == true {
                    textField(axis: .horizontal)
                } else {
                    SecureField(text: $text, prompt: Self.noPrompt) {
                        Text(title)
                    }
                    .focused($isFocused)
                }
            }
        case let .multiline(minLines):
            textEditor(minLines: minLines)
        }
    }

    private func textField(axis: Axis) -> some View {
        TextField(text: $text, prompt: Self.noPrompt, axis: axis) {
            Text(title)
        }
        .focused($isFocused)
    }

    /// Undoes how far `UITextView` insets its text by default: its text container inset vertically, and the padding
    /// either side of each line horizontally.
    private static let textEditorInsetCompensation = EdgeInsets(top: -8, leading: -5, bottom: -8, trailing: -5)

    /// A `TextEditor` rather than a vertical `TextField`, because Return in a vertical `TextField` can end editing
    /// instead of starting a new line.
    private func textEditor(minLines: Int) -> some View {
        // The editor takes the size of the same text laid out as a `Text`, so it grows as the text does, and always
        // has room for its minimum lines. The trailing space keeps the height of a trailing new line.
        Text(verbatim: text + " ")
            .lineLimit(minLines...)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .hidden()
            .overlay {
                TextEditor(text: $text)
                    .focused($isFocused)
                    .scrollContentBackground(.hidden)
                    // Line the text up with the label, and with the text of the other fields.
                    .padding(Self.textEditorInsetCompensation)
                    .accessibilityLabel(title)
            }
    }

    // MARK: - Prompt

    /// The field draws its own prompt, so a `TextField` gets an empty one rather than `nil`, which would show its label
    /// as the placeholder instead.
    private static let noPrompt = Text(verbatim: "")

    /// The label stands in for the prompt while the field is resting, so the prompt only shows once it's focused.
    private var isShowingPrompt: Bool {
        isFocused && text.isEmpty
    }

    /// Fades in once the label has floated out of the way, rather than appearing underneath it.
    @ViewBuilder
    private var promptOverlay: some View {
        if let prompt {
            Text(prompt)
                .foregroundStyle(Color(uiColor: .placeholderText))
                .lineLimit(restsLabelOnFirstLine ? nil : 1)
                .opacity(isShowingPrompt ? 1 : 0)
                .animation(isShowingPrompt ? .easeIn(duration: 0.15).delay(0.1) : nil, value: isShowingPrompt)
                .allowsHitTesting(false)
                // VoiceOver reads it as the field's hint instead.
                .accessibilityHidden(true)
        }
    }

    // MARK: - Accessories

    @ViewBuilder
    private var accessories: some View {
        switch kind {
        case .plain where isFocused && text.isNotEmpty:
            clearButton
        case let .secure(.some(isRevealed)):
            revealButton(isRevealed: isRevealed)
        case .plain, .secure, .multiline:
            EmptyView()
        }

        switch status {
        case .none:
            EmptyView()
        case .valid:
            statusIcon(systemName: "checkmark.circle.fill", color: .green)
                .accessibilityLabel("Valid")
        case .error(.none):
            statusIcon(systemName: "exclamationmark.circle.fill", color: .red)
                .accessibilityLabel("Invalid")
        case .error(.some):
            // VoiceOver reads the message instead.
            statusIcon(systemName: "exclamationmark.circle.fill", color: .red)
                .accessibilityHidden(true)
        }
    }

    private var clearButton: some View {
        Button {
            text = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Clear Text")
        .transition(.opacity)
    }

    private func revealButton(isRevealed: Binding<Bool>) -> some View {
        Button {
            let wasFocused = isFocused
            isRevealed.wrappedValue.toggle()
            // Swapping between the secure and plain field drops the keyboard, so focus the new field once it's in.
            if wasFocused {
                Task {
                    isFocused = true
                }
            }
        } label: {
            Image(systemName: isRevealed.wrappedValue ? "eye.slash" : "eye")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isRevealed.wrappedValue ? "Hide \(title)" : "Show \(title)")
    }

    private func statusIcon(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .foregroundStyle(color)
            .transition(.scale.combined(with: .opacity))
    }

    private var errorMessage: String? {
        if case let .error(.some(message)) = status {
            message
        } else {
            nil
        }
    }
}

extension LabeledTextField.Status {
    /// Flags a validation error, with its message. A value that's valid, or just not finished yet, isn't flagged.
    init(errorFrom validation: FieldValidationState) {
        if case let .error(message) = validation {
            self = .error(message: message)
        } else {
            self = .none
        }
    }
}

#Preview {
    @Previewable @State var siteName = "GitHub"
    @Previewable @State var accountName = ""
    @Previewable @State var key = "ABC!"
    @Previewable @State var password = "password"
    @Previewable @State var isPasswordRevealed = false
    @Previewable @State var description = ""

    Form {
        Section {
            LabeledTextField("Site Name", text: $siteName)
            LabeledTextField("Account Name", text: $accountName, prompt: "user@example.com")
        }

        Section {
            LabeledTextField("Key", text: $key, status: .error(message: "Invalid data"))
            LabeledTextField("Password", text: $password, kind: .secure(isRevealed: $isPasswordRevealed))
            LabeledTextField("Confirm Password", text: $password, kind: .secure(), status: .valid)
        }

        Section {
            LabeledTextField("Description", text: $description, kind: .multiline(minLines: 3))
        }
    }
}
