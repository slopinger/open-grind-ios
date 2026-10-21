import Foundation
import OpenGrindKit

/// The heights and weights the number wheels offer, within Grindr's bounds, for
/// your profile and the filters alike.
enum MeasurementOptions {
    /// Whole centimeters.
    static let centimeters = Array(
        Int(BrowseFilters.heightBounds.lowerBound)...Int(BrowseFilters.heightBounds.upperBound))

    /// In grams: whole kilograms or whole pounds, in the units of the locale.
    static let grams: [Int] = {
        let bounds = BrowseFilters.weightBounds
        if Locale.current.measurementSystem == .metric {
            let kilograms = Int((bounds.lowerBound / 1000).rounded(.up))...Int(bounds.upperBound / 1000)
            return kilograms.map { $0 * 1000 }
        }
        let gramsPerPound = 453.59237
        let pounds =
            Int((bounds.lowerBound / gramsPerPound).rounded(.up))...Int(bounds.upperBound / gramsPerPound)
        return pounds.map { Int((Double($0) * gramsPerPound).rounded()) }
    }()

    /// The option closest to `value`, so a stored value between options still has a row.
    static func nearest(to value: Double, in options: [Int]) -> Int {
        options.min { abs(Double($0) - value) < abs(Double($1) - value) } ?? Int(value)
    }
}
