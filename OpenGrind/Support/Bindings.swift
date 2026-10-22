import SwiftUI

// Binding's get and set closures are @Sendable, so what they capture must be Sendable too.

extension Binding {
    /// Whether an optional value is set, for presenting it; dismissing clears it.
    func isPresent<Wrapped: Sendable>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool> {
            wrappedValue != nil
        } set: { isPresented in
            if !isPresented { wrappedValue = nil }
        }
    }
}

extension Binding {
    /// Whether the set holds `element`, for a toggle that adds or removes it.
    func contains<Element: Hashable & Sendable>(_ element: Element) -> Binding<Bool> where Value == Set<Element> {
        Binding<Bool> {
            wrappedValue.contains(element)
        } set: { isOn in
            if isOn { wrappedValue.insert(element) } else { wrappedValue.remove(element) }
        }
    }
}

extension Set {
    /// Adds `element`, or removes it if it is there already.
    mutating func toggle(_ element: Element) {
        if remove(element) == nil { insert(element) }
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
