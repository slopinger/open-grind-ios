import Foundation

/// Geohash encoding as the Grindr API uses it: 12 characters of base32.
public enum Geohash {
    public static let precision = 12

    private static let alphabet = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    /// The geohash of a coordinate.
    public static func encode(latitude: Double, longitude: Double, precision: Int = precision)
        -> String
    {
        // Bits alternate between longitude and latitude, longitude first; 5 bits per character.
        let values = [longitude, latitude]
        var ranges = [(-180.0, 180.0), (-90.0, 90.0)]
        var hash = ""
        var bits = 0
        for index in 0..<(precision * 5) {
            let axis = index % 2
            let isUpper = values[axis] >= middle(ranges[axis])
            bisect(&ranges[axis], keepingUpper: isUpper)
            bits = bits << 1 | (isUpper ? 1 : 0)
            if index % 5 == 4 {
                hash.append(alphabet[bits])
                bits = 0
            }
        }
        return hash
    }

    /// The center of a geohash cell, or `nil` if `hash` is not a geohash.
    public static func decode(_ hash: String) -> (latitude: Double, longitude: Double)? {
        var ranges = [(-180.0, 180.0), (-90.0, 90.0)]
        var index = 0
        for character in hash.lowercased() {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            for shift in stride(from: 4, through: 0, by: -1) {
                bisect(&ranges[index % 2], keepingUpper: (value >> shift) & 1 == 1)
                index += 1
            }
        }
        return (middle(ranges[1]), middle(ranges[0]))
    }

    private static func middle(_ range: (Double, Double)) -> Double { (range.0 + range.1) / 2 }

    private static func bisect(_ range: inout (Double, Double), keepingUpper isUpper: Bool) {
        if isUpper { range.0 = middle(range) } else { range.1 = middle(range) }
    }

    /// Snaps a geohash to a grid of 0.001° (about 110 m), as Open Grind does
    /// before sending a location, so the server never sees the exact position.
    public static func coarsen(_ hash: String) -> String {
        guard let (latitude, longitude) = decode(hash) else { return hash }
        func snap(_ degrees: Double) -> Double { (degrees * 1000).rounded() / 1000 }
        return encode(latitude: snap(latitude), longitude: snap(longitude))
    }
}
