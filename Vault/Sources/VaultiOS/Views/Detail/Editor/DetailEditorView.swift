import Foundation
import SwiftUI
import VaultFeed

extension EnvironmentValues {
    /// What Back does on the first step of a walkthrough, which has no step of its own to go back to.
    ///
    /// The new-item sheet sets it to return to choosing the kind of item. Without it, the first step has no Back.
    @Entry var goBackFromFirstEditorStep: GoBackFromFirstEditorStepAction?
}

/// Goes back from the first step of a walkthrough, to whatever came before the editor.
struct GoBackFromFirstEditorStepAction: Equatable, Sendable {
    /// Identifies where Back goes, so the environment only changes when that does, not every time the closure is
    /// made again.
    var id: UUID
    var action: @MainActor () -> Void

    @MainActor
    func callAsFunction() {
        action()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

/// An item's editor, the same for every kind of item.
///
/// Creating an item walks through its steps one at a time, each like its own bottom sheet: the sheet fits the step,
/// changing height as the next one slides in, with Back and Continue along the bottom. Editing an item starts on an
/// overview instead, which opens any step straight away.
///
/// While walking through, each step reports the height it needs to the sheet's `fittedSheetHeightReporter`, and the
/// new-item sheet sizes itself to it.
///
/// The steps swap within the one sheet, rather than stacking sheets, so the item's lock and hiding (which cover the
/// whole sheet) always cover whichever step is showing.
struct DetailEditorView<ViewModel: DetailViewModel, StepContent: View>: View {
    @Bindable var viewModel: ViewModel
    var kind: DetailEditorItemKind
    var identity: DetailEditorItemIdentity
    /// Shows a delete button on the overview, which calls this.
    var delete: (() -> Void)?
    @ViewBuilder var stepContent: (DetailEditorStep) -> StepContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.goBackFromFirstEditorStep) private var goBackFromFirstStep
    @Environment(\.fittedSheetHeightReporter) private var sheetHeightReporter
    /// The step on screen, or `nil` for the overview. Follows the flow's step a moment later, so the outgoing screen
    /// can take on the new direction before it leaves.
    @State private var displayedStep: DetailEditorStep?
    @State private var direction: DetailEditorFlow.Direction = .forward
    @State private var actionBarHeight: CGFloat = 0

    init(
        viewModel: ViewModel,
        kind: DetailEditorItemKind,
        identity: DetailEditorItemIdentity,
        delete: (() -> Void)? = nil,
        @ViewBuilder stepContent: @escaping (DetailEditorStep) -> StepContent,
    ) {
        self.viewModel = viewModel
        self.kind = kind
        self.identity = identity
        self.delete = delete
        self.stepContent = stepContent
        _displayedStep = State(initialValue: viewModel.editorFlow.currentStep)
    }

    var body: some View {
        ZStack {
            screen
                .id(displayedStep)
                .transition(transition)
        }
        .onChange(of: viewModel.editorFlow.currentStep) { _, newStep in
            direction = viewModel.editorFlow.direction
            // A separate update, so the outgoing screen has already taken on the new direction when it leaves.
            Task { @MainActor in
                withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .snappy(duration: 0.4)) {
                    displayedStep = newStep
                }
                // VoiceOver moves to the new step, as it would for a new screen.
                AccessibilityNotification.ScreenChanged().post()
            }
        }
    }

    private var isGuided: Bool {
        viewModel.editorFlow.style == .guided
    }

    // MARK: - Screens

    @ViewBuilder
    private var screen: some View {
        if let step = displayedStep {
            stepScreen(step)
        } else {
            Form {
                DetailEditorOverview(
                    kind: kind,
                    identity: identity,
                    steps: viewModel.editorFlow.steps,
                    summary: viewModel.editorSummary(for:),
                    open: viewModel.showEditorStep,
                    delete: delete,
                )
            }
        }
    }

    private func stepScreen(_ step: DetailEditorStep) -> some View {
        Form {
            Section {
                DetailEditorStepHeader(step: step, kind: kind, position: position(of: step))
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

            stepContent(step)
                .listRowBackground(DetailEditorRowBackground())
        }
        .environment(\.isInGuidedDetailEditor, isGuided)
        // Lets the sheet's glass show through while stepping through, like the new-item picker.
        .scrollContentBackground(isGuided ? .hidden : .automatic)
        .onFittedSheetHeightChange(bottomBarHeight: isGuided ? actionBarHeight : 0) { height in
            // The outgoing step can still report while it slides away.
            guard isGuided, step == displayedStep else { return }
            sheetHeightReporter?(height)
        }
        .safeAreaBar(edge: .bottom) {
            if isGuided {
                actionBar(for: step)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        actionBarHeight = height
                    }
            }
        }
    }

    private func actionBar(for step: DetailEditorStep) -> some View {
        let flow = viewModel.editorFlow
        let isFirstStep = flow.steps.first == step
        let isLastStep = flow.steps.last == step
        return DetailEditorActionBar(
            showsBackButton: !isFirstStep || goBackFromFirstStep != nil,
            primaryTitle: isLastStep ? kind.addTitle : "Continue",
            isPrimaryEnabled: isLastStep ? viewModel.editingModel.isValid : viewModel.isEditorStepComplete(step),
            goBack: {
                if isFirstStep, let goBackFromFirstStep {
                    goBackFromFirstStep()
                } else {
                    viewModel.goBackInEditor()
                }
            },
            primaryAction: {
                if isLastStep {
                    await viewModel.saveChanges()
                } else {
                    viewModel.continueInEditor()
                }
            },
        )
    }

    private func position(of step: DetailEditorStep) -> DetailEditorStepHeader.Position? {
        let steps = viewModel.editorFlow.steps
        guard isGuided, let index = steps.firstIndex(of: step) else { return nil }
        return .init(number: index + 1, count: steps.count)
    }

    // MARK: - Presentation

    private var transition: AnyTransition {
        if reduceMotion {
            .opacity
        } else {
            switch direction {
            case .forward: .push(from: .trailing)
            case .backward: .push(from: .leading)
            }
        }
    }
}
