import Combine
import Foundation

public final class SettingsViewModel {
    public init() {}
}

// MARK: - Strings

extension SettingsViewModel {
    public var title: String {
        localized(key: "home.title")
    }

    public var viewOptionsSectionTitle: String {
        localized(key: "home.header.viewOptions.title")
    }

    public var policyAndLegacySectionTitle: String {
        localized(key: "home.header.policyAndLegal.title")
    }

    public var aboutTitle: String {
        localized(key: "about.title")
    }

    public var helpTitle: String {
        "FAQs"
    }

    public var previewSizeTitle: String {
        localized(key: "previewSize.title")
    }

    public var pasteTTLTitle: String {
        localized(key: "pasteTTL.title")
    }

    public var codeTapActionTitle: String {
        localized(key: "codeTapAction.title")
    }

    public var saveBackupTitle: String {
        localized(key: "saveBackup.title")
    }

    public var restoreBackupTitle: String {
        localized(key: "restoreBackup.title")
    }

    public var openSourceTitle: String {
        localized(key: "openSource.title")
    }

    public var thirdPartyTitle: String {
        localized(key: "thirdPartyLibraries.title")
    }

    public var privacyPolicyTitle: String {
        localized(key: "privacyPolicy.title")
    }

    public var termsOfUseTitle: String {
        localized(key: "termsOfUse.title")
    }
}
