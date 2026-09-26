import Foundation
import Testing
@testable import VaultFeed

struct AppLockPasswordRulesTests {
    @Test(arguments: ["", "a", "short", "7chars!"])
    func problem_fewerThanEightCharacters_isTooShort(password: String) {
        #expect(AppLockPasswordRules.problem(with: password) == .tooShort)
    }

    /// Counted as the user sees them, so an accented letter or an emoji is one character, however it's encoded.
    @Test
    func problem_countsCharactersAsTheyLook() {
        #expect(AppLockPasswordRules.problem(with: "cafe\u{301}🔐!") == .tooShort)
        #expect(AppLockPasswordRules.problem(with: "cafe\u{301}🔐!ab") == nil)
    }

    @Test(arguments: ["12345678", "0000 0000", "١٢٣٤٥٦٧٨", "        "])
    func problem_onlyNumbers_isRejectedLikeAPIN(password: String) {
        #expect(AppLockPasswordRules.problem(with: password) == .onlyNumbers)
    }

    @Test(arguments: ["correct horse", "12345678a", "passw0rd", "!2345678"])
    func problem_realPassword_isNone(password: String) {
        #expect(AppLockPasswordRules.problem(with: password) == nil)
    }
}
