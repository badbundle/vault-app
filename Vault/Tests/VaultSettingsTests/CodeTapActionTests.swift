import Foundation
import Testing
@testable import VaultSettings

struct CodeTapActionTests {
    @Test
    func default_isCopy() {
        #expect(CodeTapAction.default == .copy)
    }

    @Test
    func localizedName_namesEachAction() {
        #expect(CodeTapAction.copy.localizedName == "Copy")
        #expect(CodeTapAction.showDetails.localizedName == "Show Details")
    }
}
