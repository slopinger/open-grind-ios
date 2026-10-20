import SwiftUI

extension Binding {
    /// Whether an optional value is set, for presenting it; dismissing clears it.
    func isPresent<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool> {
            wrappedValue != nil
        } set: { isPresented in
            if !isPresented { wrappedValue = nil }
        }
    }
}

extension Binding where Value == String? {
    /// Whether the wheel `id` is the open one; a form keeps one open at a time.
    func isOpen(_ id: String) -> Binding<Bool> {
        Binding<Bool> {
            wrappedValue == id
        } set: { isOpen in
            wrappedValue = isOpen ? id : nil
        }
    }
}
