import Foundation
import FoundationExtensions
import Testing
@testable import VaultSettings

struct ThirdPartyLibrariesLoaderTests {
    @Test
    func load_loadsLibrariesFileFromRealDiskFile() async throws {
        let fetcher = FileSystemLocalResourceFetcher()
        let sut = makeSUT(resourceFetcher: fetcher)

        let loaded = try await sut.load()

        #expect(loaded.map(\.name) == [
            "SwiftUI-Shimmer",
            "CryptoSwift",
            "SnapshotTesting",
            "swiftui-toasts",
            "Defaults",
            "CodeScanner",
            "swift-security",
            "swift-markdown-ui",
            "Lucide",
            "BIP39 wordlists (python-mnemonic)",
            "SLIP-39 wordlist (python-shamir-mnemonic)",
            "Monero wordlist",
            "Electrum",
        ])
    }

    @Test
    func load_parsesValuesCorrectly() async throws {
        let exampleFile = """
        {
            "libraries": [
                {
                    "name": "First",
                    "url": "https://github.com/first/first",
                    "licence": "My First Licence"
                },
                {
                    "name": "Second",
                    "url": "https://github.com/second/second",
                    "licence": "My Second Licence"
                },
            ]
        }
        """
        let fetcher = StubLocalResourceFetcher(stubData: Data(exampleFile.utf8))
        let sut = makeSUT(resourceFetcher: fetcher)

        let loaded = try await sut.load()

        #expect(loaded.map(\.name) == ["First", "Second"])
        #expect(loaded.map(\.licence) == ["My First Licence", "My Second Licence"])
        #expect(loaded.map(\.url.absoluteString) == [
            "https://github.com/first/first",
            "https://github.com/second/second",
        ])
    }
}

extension ThirdPartyLibrariesLoaderTests {
    private func makeSUT(resourceFetcher: any LocalResourceFetcher) -> ThirdPartyLibraryLoader {
        ThirdPartyLibraryLoader(resourceFetcher: resourceFetcher)
    }
}
