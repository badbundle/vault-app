import Combine
import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultSettings
@testable import VaultiOSAutofill

@MainActor
struct VaultAutofillViewModelTests {
    @Test
    func init_displaysNoFeature() throws {
        let sut = try makeSUT()

        #expect(sut.feature == nil)
    }

    @Test
    func show_setsDisplayedFeature() throws {
        let sut = try makeSUT()

        sut.show(feature: .showAllCodesSelector)

        #expect(sut.feature == .showAllCodesSelector)
    }

    @Test
    func dismissConfiguration_publishesDismiss() throws {
        let sut = try makeSUT()
        var dismissCount = 0
        let cancellable = sut.configurationDismissPublisher.sink { dismissCount += 1 }
        defer { cancellable.cancel() }

        sut.dismissConfiguration()

        #expect(dismissCount == 1)
    }

    @Test
    func textToInsertPublisher_filtersBlankStrings() throws {
        let sut = try makeSUT()
        var received = [String]()
        let cancellable = sut.textToInsertPublisher.sink { received.append($0) }
        defer { cancellable.cancel() }

        sut.textToInsertSubject.send("123456")
        sut.textToInsertSubject.send("")
        sut.textToInsertSubject.send("   ")
        sut.textToInsertSubject.send("654321")

        #expect(received == ["123456", "654321"])
    }

    @Test
    func cancelRequestPublisher_forwardsReason() throws {
        let sut = try makeSUT()
        var received = [VaultAutofillViewModel.RequestCancelReason]()
        let cancellable = sut.cancelRequestPublisher.sink { received.append($0) }
        defer { cancellable.cancel() }

        sut.cancelRequestSubject.send(.userCancelled)

        #expect(received == [.userCancelled])
    }
}

// MARK: - Helpers

extension VaultAutofillViewModelTests {
    private func makeSUT() throws -> VaultAutofillViewModel {
        try VaultAutofillViewModel(
            localSettings: LocalSettings(defaults: Defaults.nonPersistent()),
        )
    }
}
