import Foundation

/// Where the user is in an item's editor.
///
/// A new item is made by walking through the editor's steps in order: the next step only opens once the ones before
/// it are complete. An existing item's editor opens on an overview of its steps instead, and any of them can be
/// opened straight from there, so a change doesn't mean going through the whole editor.
public struct DetailEditorFlow: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        /// The steps are walked through in order, as when creating an item.
        case guided
        /// An overview of the steps, any of which can be opened, as when editing an item.
        case overview
    }

    /// Which way the editor last moved, so the change can animate the right way.
    public enum Direction: Equatable, Sendable {
        case forward
        case backward
    }

    /// The steps this editor has, in order. Never empty.
    public let steps: [DetailEditorStep]
    public let style: Style
    /// The step being shown, or `nil` for the overview.
    public private(set) var currentStep: DetailEditorStep?
    public private(set) var direction: Direction = .forward

    /// - Parameter startingStep: The step to open on, if it's one of `steps`. Otherwise a guided editor opens on its
    ///   first step and an overview on the overview.
    public init(steps: [DetailEditorStep], style: Style, startingAt startingStep: DetailEditorStep? = nil) {
        precondition(steps.isNotEmpty, "An editor needs at least one step")
        self.steps = steps
        self.style = style
        let startingStep = startingStep.flatMap { steps.contains($0) ? $0 : nil }
        currentStep = switch style {
        case .guided: startingStep ?? steps.first
        case .overview: startingStep
        }
    }

    public var isShowingOverview: Bool {
        currentStep == nil
    }

    /// The index of the step being shown in `steps`, or `nil` for the overview.
    public var currentStepIndex: Int? {
        currentStep.flatMap(steps.firstIndex(of:))
    }

    public var nextStep: DetailEditorStep? {
        guard let index = currentStepIndex, index + 1 < steps.count else { return nil }
        return steps[index + 1]
    }

    public var previousStep: DetailEditorStep? {
        guard let index = currentStepIndex, index > 0 else { return nil }
        return steps[index - 1]
    }

    public var isOnLastStep: Bool {
        currentStep != nil && nextStep == nil
    }

    /// Whether `step` can be opened now.
    ///
    /// From the overview every step can. In a guided editor, a step only opens once every step before it is
    /// complete.
    public func isReachable(_ step: DetailEditorStep, isComplete: (DetailEditorStep) -> Bool) -> Bool {
        guard let index = steps.firstIndex(of: step) else { return false }
        switch style {
        case .overview: return true
        case .guided: return steps[..<index].allSatisfy(isComplete)
        }
    }

    /// Opens `step`, if it's one of this editor's steps. Doesn't check that it's reachable.
    public mutating func show(_ step: DetailEditorStep) {
        guard let index = steps.firstIndex(of: step) else { return }
        direction = if let currentStepIndex, index < currentStepIndex {
            .backward
        } else {
            .forward
        }
        currentStep = step
    }

    /// Moves on to the next step, if there is one.
    public mutating func goForward() {
        guard let nextStep else { return }
        direction = .forward
        currentStep = nextStep
    }

    /// Moves back: to the previous step when guided, or to the overview.
    public mutating func goBack() {
        switch style {
        case .guided:
            guard let previousStep else { return }
            direction = .backward
            currentStep = previousStep
        case .overview:
            showOverview()
        }
    }

    /// Returns to the overview. A guided editor has no overview, so stays where it is.
    public mutating func showOverview() {
        guard style == .overview, currentStep != nil else { return }
        direction = .backward
        currentStep = nil
    }
}
