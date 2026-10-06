import Testing
import VaultFeed
@testable import VaultMac

struct VaultMacWindowTests {
    @Test
    func title_isOnlyEverTheAppsName() {
        #expect(VaultMacWindow.main.title == "Vault")
        #expect(VaultMacWindow.about.title == "About Vault")
        #expect(VaultMacWindow.help.title == "Vault Help")
    }

    @Test
    func id_isDifferentForEachWindow() {
        #expect(Set(VaultMacWindow.allCases.map(\.id)).count == VaultMacWindow.allCases.count)
    }
}

struct VaultMacSharedStorageTests {
    @Test
    func appGroupID_isTheMacsTeamPrefixedGroup() {
        #expect(VaultSharedStorage.appGroupID == "442P244AFS.com.badbundle.vault")
    }
}
