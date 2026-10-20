import Foundation

/// Geohash encoding as the Grindr API uses it: 12 characters of base32.
public enum Geohash {
    public static let precision = 12

    private static let alphabet = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    /// The geohash of a coordinate.
    public static func encode(latitude: Double, longitude: Double, precision: Int = precision)
        -> String
    {
        var latitudeRange = (-90.0, 90.0)
        var longitudeRange = (-180.0, 180.0)
        var hash = ""
        var bits = 0
        var bit = 0
        var isLongitude = true

        while hash.count < precision {
            if isLongitude {
                let mid = (longitudeRange.0 + longitudeRange.1) / 2
                if longitude >= mid {
                    bits = bits << 1 | 1
                    longitudeRange.0 = mid
                } else {
                    bits <<= 1
                    longitudeRange.1 = mid
                }
            } else {
                let mid = (latitudeRange.0 + latitudeRange.1) / 2
                if latitude >= mid {
                    bits = bits << 1 | 1
                    latitudeRange.0 = mid
                } else {
                    bits <<= 1
                    latitudeRange.1 = mid
                }
            }
            isLongitude.toggle()
            bit += 1
            if bit == 5 {
                hash.append(alphabet[bits])
                bits = 0
                bit = 0
            }
        }
        return hash
    }

    /// The center of a geohash cell, or `nil` if `hash` is not a geohash.
    public static func decode(_ hash: String) -> (latitude: Double, longitude: Double)? {
        var latitudeRange = (-90.0, 90.0)
        var longitudeRange = (-180.0, 180.0)
        var isLongitude = true

        for character in hash.lowercased() {
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            for shift in stride(from: 4, through: 0, by: -1) {
                let isSet = (index >> shift) & 1 == 1
                if isLongitude {
                    let mid = (longitudeRange.0 + longitudeRange.1) / 2
                    if isSet { longitudeRange.0 = mid } else { longitudeRange.1 = mid }
                } else {
                    let mid = (latitudeRange.0 + latitudeRange.1) / 2
                    if isSet { latitudeRange.0 = mid } else { latitudeRange.1 = mid }
                }
                isLongitude.toggle()
            }
        }
        return ((latitudeRange.0 + latitudeRange.1) / 2, (longitudeRange.0 + longitudeRange.1) / 2)
    }

    /// Snaps a geohash to a grid of 0.001° (about 110 m), as Open Grind does
    /// before sending a location, so the server never sees the exact position.
    public static func coarsen(_ hash: String) -> String {
        guard let (latitude, longitude) = decode(hash) else { return hash }
        func snap(_ degrees: Double) -> Double { (degrees * 1000).rounded() / 1000 }
        return encode(latitude: snap(latitude), longitude: snap(longitude))
    }
}
