import Foundation
import Testing
@testable import VaultFeed

struct AppCoverTests {
    @Test
    func required_nothingToHide_isNone() {
        let cover = AppCover.required(
            isPrivacyCoverRequired: false,
            hidesVaultWhileScreenCaptured: true,
            isScreenCaptured: false,
        )

        #expect(cover == nil)
    }

    @Test
    func required_screenCaptured_coversTheVault() {
        // With the app lock off: the setting is independent of it.
        let cover = AppCover.required(
            isPrivacyCoverRequired: false,
            hidesVaultWhileScreenCaptured: true,
            isScreenCaptured: true,
        )

        #expect(cover == .screenCapture)
    }

    @Test
    func required_screenCaptured_settingOff_isNone() {
        let cover = AppCover.required(
            isPrivacyCoverRequired: false,
            hidesVaultWhileScreenCaptured: false,
            isScreenCaptured: true,
        )

        #expect(cover == nil)
    }

    @Test
    func required_privacyCoverRequired_isPrivacy() {
        let cover = AppCover.required(
            isPrivacyCoverRequired: true,
            hidesVaultWhileScreenCaptured: true,
            isScreenCaptured: false,
        )

        #expect(cover == .privacy)
    }

    @Test
    func required_privacyCoverRequired_settingOffAndCaptured_isStillPrivacy() {
        // Turning off the capture cover never takes away the app lock's cover.
        let cover = AppCover.required(
            isPrivacyCoverRequired: true,
            hidesVaultWhileScreenCaptured: false,
            isScreenCaptured: true,
        )

        #expect(cover == .privacy)
    }

    @Test
    func required_capturedAndPrivacyCoverRequired_isScreenCapture() {
        // Pulling down Control Center mid-recording keeps the same cover, rather than swapping it and back.
        let cover = AppCover.required(
            isPrivacyCoverRequired: true,
            hidesVaultWhileScreenCaptured: true,
            isScreenCaptured: true,
        )

        #expect(cover == .screenCapture)
    }
}
