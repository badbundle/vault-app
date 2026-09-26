import Foundation
import SwiftUI
import VaultFeed

/// An item's editor, the same for every kind of item.
///
/// Creating an item walks through its steps one at a time, each like its own bottom sheet: the sheet fits the step,
/// changing height as the next one slides in, with Back and Continue along the bottom. Editing an item starts on an
/// overview instead, which opens any step straight away.
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
    /// The step on screen, or `nil` for the overview. Follows the flow's step a moment later, so the outgoing screen
    /// can take on the new direction before it leaves.
    @State private var displayedStep: DetailEditorStep?
    @State private var direction: DetailEditorFlow.Direction = .forward
    /// The height the sheet needs to show all of the current step.
    @State private var fittedHeight: CGFloat = 0
    @State private var measurementPass = 0

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
        .presentationDetents(isGuided ? [fittedDetent] : [.large])
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
        .onScrollGeometryChange(for: FittedHeightMeasurement.self) { geometry in
            FittedHeightMeasurement(
                pass: measurementPass,
                height: geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom,
            )
        } action: { _, measurement in
            // The outgoing step can still report while it slides away.
            guard step == displayedStep else { return }
            fittedHeight = measurement.height
        }
        // A new step's first measurement isn't reported as a change, so it's asked for again once it's on screen.
        .onAppear {
            measurementPass += 1
        }
        .safeAreaBar(edge: .bottom) {
            if isGuided {
                actionBar(for: step)
            }
        }
    }

    private func actionBar(for step: DetailEditorStep) -> some View {
        let flow = viewModel.editorFlow
        let isLastStep = flow.steps.last == step
        return DetailEditorActionBar(
            showsBackButton: flow.steps.first != step,
            primaryTitle: isLastStep ? kind.addTitle : "Continue",
            isPrimaryEnabled: isLastStep ? viewModel.editingModel.isValid : viewModel.isEditorStepComplete(step),
            goBack: viewModel.goBackInEditor,
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

    /// Fits the sheet to the step, until the step is taller than the sheet can be.
    private var fittedDetent: PresentationDetent {
        fittedHeight > 0 ? .height(fittedHeight) : .large
    }

    private struct FittedHeightMeasurement: Equatable {
        var pass: Int
        var height: CGFloat
    }

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
