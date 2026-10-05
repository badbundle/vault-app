import Testing

extension Trait where Self == ConditionTrait {
    /// For a test that makes a PDF backup, which only iOS can do until the Mac renders PDFs too (VAULT-104).
    public static var rendersPDFBackups: Self {
        #if canImport(UIKit)
        .enabled(if: true)
        #else
        .disabled("The Mac renders PDF backups from VAULT-104")
        #endif
    }
}
