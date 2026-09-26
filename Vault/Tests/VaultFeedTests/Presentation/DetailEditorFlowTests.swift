import Foundation
import Testing
import VaultFeed

struct DetailEditorFlowTests {
    // MARK: - Starting

    @Test
    func init_guidedStartsOnFirstStep() {
        let sut = DetailEditorFlow(steps: [.details, .appearance, .security], style: .guided)

        #expect(sut.currentStep == .details)
        #expect(sut.currentStepIndex == 0)
        #expect(sut.isShowingOverview == false)
    }

    @Test
    func init_overviewStartsOnOverview() {
        let sut = DetailEditorFlow(steps: DetailEditorStep.allCases, style: .overview)

        #expect(sut.currentStep == nil)
        #expect(sut.currentStepIndex == nil)
        #expect(sut.isShowingOverview)
    }

    @Test(arguments: [DetailEditorFlow.Style.guided, .overview])
    func init_startsOnStartingStep(style: DetailEditorFlow.Style) {
        let sut = DetailEditorFlow(steps: DetailEditorStep.allCases, style: style, startingAt: .appearance)

        #expect(sut.currentStep == .appearance)
    }

    @Test
    func init_ignoresStartingStepItDoesNotHave() {
        let guided = DetailEditorFlow(steps: [.content, .security], style: .guided, startingAt: .details)
        let overview = DetailEditorFlow(steps: [.content, .security], style: .overview, startingAt: .details)

        #expect(guided.currentStep == .content)
        #expect(overview.currentStep == nil)
    }

    // MARK: - Next and previous

    @Test
    func nextAndPreviousStep_followTheSteps() {
        var sut = DetailEditorFlow(steps: [.content, .appearance, .security], style: .guided)

        #expect(sut.previousStep == nil)
        #expect(sut.nextStep == .appearance)
        #expect(sut.isOnLastStep == false)

        sut.goForward()
        #expect(sut.previousStep == .content)
        #expect(sut.nextStep == .security)

        sut.goForward()
        #expect(sut.nextStep == nil)
        #expect(sut.isOnLastStep)
    }

    @Test
    func nextAndPreviousStep_noneOnOverview() {
        let sut = DetailEditorFlow(steps: DetailEditorStep.allCases, style: .overview)

        #expect(sut.nextStep == nil)
        #expect(sut.previousStep == nil)
        #expect(sut.isOnLastStep == false)
    }

    // MARK: - Moving

    @Test
    func goForward_movesForwardAndStopsAtLastStep() {
        var sut = DetailEditorFlow(steps: [.content, .security], style: .guided)

        sut.goForward()
        #expect(sut.currentStep == .security)
        #expect(sut.direction == .forward)

        sut.goForward()
        #expect(sut.currentStep == .security)
    }

    @Test
    func goBack_guidedMovesBackAndStopsAtFirstStep() {
        var sut = DetailEditorFlow(steps: [.content, .security], style: .guided, startingAt: .security)

        sut.goBack()
        #expect(sut.currentStep == .content)
        #expect(sut.direction == .backward)

        sut.goBack()
        #expect(sut.currentStep == .content)
    }

    @Test
    func goBack_overviewReturnsToOverview() {
        var sut = DetailEditorFlow(steps: DetailEditorStep.allCases, style: .overview)
        sut.show(.security)

        sut.goBack()

        #expect(sut.isShowingOverview)
        #expect(sut.direction == .backward)
    }

    @Test
    func show_setsDirectionFromPosition() {
        var sut = DetailEditorFlow(steps: DetailEditorStep.allCases, style: .guided, startingAt: .appearance)

        sut.show(.security)
        #expect(sut.currentStep == .security)
        #expect(sut.direction == .forward)

        sut.show(.content)
        #expect(sut.currentStep == .content)
        #expect(sut.direction == .backward)
    }

    @Test
    func show_fromOverviewMovesForward() {
        var sut = DetailEditorFlow(steps: DetailEditorStep.allCases, style: .overview)

        sut.show(.content)

        #expect(sut.currentStep == .content)
        #expect(sut.direction == .forward)
    }

    @Test
    func show_ignoresStepItDoesNotHave() {
        var sut = DetailEditorFlow(steps: [.content, .security], style: .guided)

        sut.show(.details)

        #expect(sut.currentStep == .content)
    }

    @Test
    func showOverview_guidedHasNoOverview() {
        var sut = DetailEditorFlow(steps: DetailEditorStep.allCases, style: .guided)

        sut.showOverview()

        #expect(sut.currentStep == .content)
    }

    // MARK: - Reachable

    @Test
    func isReachable_guidedNeedsEveryEarlierStepComplete() {
        let sut = DetailEditorFlow(steps: DetailEditorStep.allCases, style: .guided)
        let isComplete: (DetailEditorStep) -> Bool = { $0 != .details }

        #expect(sut.isReachable(.content, isComplete: isComplete))
        #expect(sut.isReachable(.details, isComplete: isComplete))
        #expect(sut.isReachable(.appearance, isComplete: isComplete) == false)
        #expect(sut.isReachable(.security, isComplete: isComplete) == false)
    }

    @Test
    func isReachable_overviewReachesEveryStep() {
        let sut = DetailEditorFlow(steps: DetailEditorStep.allCases, style: .overview)

        for step in DetailEditorStep.allCases {
            #expect(sut.isReachable(step) { _ in false })
        }
    }

    @Test
    func isReachable_neverReachesStepItDoesNotHave() {
        let sut = DetailEditorFlow(steps: [.content, .security], style: .overview)

        #expect(sut.isReachable(.details) { _ in true } == false)
    }
}
