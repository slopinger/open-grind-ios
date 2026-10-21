import SwiftUI

/// A small capsule in the brand colour with a count or a word, such as an
/// unread count or "Mutual".
struct BrandBadge: View {
    let text: Text
    /// Grey, e.g. for muted conversations.
    var isMuted = false
    /// The smaller size, for badges on photos.
    var isSmall = false

    init(_ text: Text, isMuted: Bool = false, isSmall: Bool = false) {
        self.text = text
        self.isMuted = isMuted
        self.isSmall = isSmall
    }

    var body: some View {
        text
            .font(isSmall ? .caption2.bold() : .caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(isMuted ? Color.white : Color.brandForeground)
            .padding(.horizontal, isSmall ? 6 : 7)
            .padding(.vertical, 2)
            // A circle for single digits.
            .frame(minWidth: isSmall ? nil : 22)
            .background(isMuted ? Color.secondary : Color.brand, in: .capsule)
    }
}
