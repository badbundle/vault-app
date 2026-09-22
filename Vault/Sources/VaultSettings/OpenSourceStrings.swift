import Foundation

public enum OpenSourceStrings {
    public static var title: String {
        localized(key: "openSource.title")
    }

    public static var about: String {
        localized(key: "openSource.about")
    }

    public static var viewOnGitHub: String {
        localized(key: "openSource.viewOnGitHub")
    }

    public static let openSourceLink = URL(string: "https://github.com/badbundle/vault-app")!
}
