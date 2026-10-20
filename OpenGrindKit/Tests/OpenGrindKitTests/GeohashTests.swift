import Testing

@testable import OpenGrindKit

struct GeohashTests {
    @Test func encodesKnownLocations() {
        // Reference values from geohash.org.
        #expect(Geohash.encode(latitude: 57.64911, longitude: 10.40744) == "u4pruydqqvj8")
        #expect(Geohash.encode(latitude: 0, longitude: 0) == "s00000000000")
    }

    @Test func decodesToTheCellCenter() throws {
        let (latitude, longitude) = try #require(Geohash.decode("u4pruydqqvj8"))
        #expect(abs(latitude - 57.64911) < 0.0001)
        #expect(abs(longitude - 10.40744) < 0.0001)
        #expect(Geohash.decode("not a hash!") == nil)
    }

    @Test func coarseningSnapsToAThousandthOfADegree() throws {
        let precise = Geohash.encode(latitude: 52.520_08, longitude: 13.404_95)
        let (latitude, longitude) = try #require(Geohash.decode(Geohash.coarsen(precise)))
        #expect(abs(latitude - 52.520) < 0.000_01)
        #expect(abs(longitude - 13.405) < 0.000_01)
        #expect(Geohash.coarsen(Geohash.coarsen(precise)) == Geohash.coarsen(precise))
    }
}
