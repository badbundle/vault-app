import Foundation

extension UInt64 {
    var data: Data {
        var int = self
        return Data(bytes: &int, count: MemoryLayout.size(ofValue: self))
    }
}

extension Data {
    /// An unsafe operation to cast the bytes of this data to the provided type.
    ///
    /// `Data` gives no alignment guarantee for its backing buffer — a slice can start at any byte
    /// offset — so the load must tolerate misalignment. An aligned `load` traps at runtime instead.
    func asType<T>(_: T.Type) -> T {
        withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            ptr.loadUnaligned(as: T.self)
        }
    }

    /// Interpret the UTF-8 bytes of the provided string as data.
    public init(byteString: String) {
        self.init(byteString.utf8)
    }
}
