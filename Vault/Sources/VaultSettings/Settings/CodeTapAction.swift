import Foundation
import FoundationExtensions

/// What tapping a code in the vault does. The other one is in the code's menu.
public enum CodeTapAction: String, Codable, Equatable, Hashable, CaseIterable, Sendable, IdentifiableSelf {
    /// Copy the code, as the app always has.
    case copy
    /// Open the code's details.
    case showDetails
}

extension CodeTapAction {
    public static let `default`: CodeTapAction = .copy
}

extension CodeTapAction {
    public var localizedName: String {
        switch self {
        case .copy:
            localized(key: "codeTapAction.copy")
        case .showDetails:
            localized(key: "codeTapAction.showDetails")
        }
    }
}
