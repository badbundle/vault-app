import Foundation
import Testing
import VaultCore

struct OTPAuthSecretTests {
    /// The secret stays out of every textual representation, including those of the code that holds it.
    @Test
    func description_leavesOutTheSecret() throws {
        let secret = try OTPAuthSecret.base32EncodedString("JBSWY3DPEHPK3PXP")
        let code = OTPAuthCode(type: .totp(), data: .init(secret: secret, accountName: "account"))

        let representations = [
            String(describing: secret),
            String(reflecting: secret),
            "\(secret)",
            String(describing: [secret]),
            String(describing: Optional(secret) as Any),
            dumped(secret),
            String(describing: code),
            String(reflecting: code),
            dumped(code),
        ]
        for representation in representations {
            #expect(!representation.contains("JBSWY3DPEHPK3PXP"))
            #expect(!representation.lowercased().contains("48656c6c6f21deadbeef"), "The secret's bytes, in hex")
            #expect(!representation.contains("222, 173, 190, 239"), "The secret's last bytes, in decimal")
            #expect(!representation.contains("- 222"), "A byte of the secret, as `dump` lists it")
            #expect(representation.contains("redacted"))
        }
    }

    @Test
    func mirror_showsOnlyTheFormat() throws {
        let secret = try OTPAuthSecret.base32EncodedString("JBSWY3DPEHPK3PXP")

        let children = Mirror(reflecting: secret).children.map(\.label)

        #expect(children == ["format"])
    }

    private func dumped(_ value: some Any) -> String {
        var output = ""
        dump(value, to: &output)
        return output
    }
}
