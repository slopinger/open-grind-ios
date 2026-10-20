import Foundation

/// Where Grindr's CDN serves media.
public enum MediaURL {
    public enum ProfileImageSize: Sendable {
        /// 320×320, for grids, lists and avatars.
        case thumbnail
        /// 1024×1024, for full screen photos.
        case full

        var pathComponent: String {
            switch self {
            case .thumbnail: "thumb/320x320"
            case .full: "profile/1024x1024"
            }
        }
    }

    /// Hosts the transport fetches media from. Anything else is never loaded.
    static let allowedHosts: Set<String> = [
        "cdns.grindr.com", "api.giphy.com", "media.giphy.com", "media0.giphy.com", "media1.giphy.com",
        "media2.giphy.com", "media3.giphy.com", "media4.giphy.com",
    ]

    /// A profile photo by its media hash.
    public static func profileImage(_ mediaHash: String, size: ProfileImageSize) -> URL {
        // Media hashes are hex, so this never fails for well-formed input.
        URL(string: "https://cdns.grindr.com/images/\(size.pathComponent)/\(mediaHash)")
            ?? URL(string: "https://cdns.grindr.com/images/")!
    }

    /// A gaymoji sticker by the `imageHash` of a Gaymoji message, e.g. `gaymoji/1_2_Yass.png`.
    public static func gaymoji(_ imageHash: String) -> URL? {
        let id =
            imageHash.hasPrefix("gaymoji/") ? String(imageHash.dropFirst("gaymoji/".count)) : imageHash
        guard !id.isEmpty,
            let encoded = id.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics.union(["-", "_", "."]))
        else { return nil }
        return URL(string: "https://cdns.grindr.com/grindr/chat/gaymoji/\(encoded)")
    }

    /// A gaymoji's readable name, e.g. "Yass" for `gaymoji/1_2_Yass.png`.
    public static func gaymojiLabel(_ imageHash: String) -> String {
        var name = imageHash.split(separator: "/").last.map(String.init) ?? imageHash
        if name.hasSuffix(".png") { name.removeLast(4) }
        let words = name.split(separator: "_")
        // Leading numbers and single letters only sort the sticker sheet.
        let label = words.drop { $0.allSatisfy(\.isNumber) || $0.count == 1 }.joined(separator: " ")
        return label.isEmpty ? words.joined(separator: " ") : label
    }

    /// The media hash in a profile photo thumbnail URL, such as a grid tile's.
    public static func mediaHash(ofThumbnail url: URL) -> String? {
        let thumbnail = "/images/\(ProfileImageSize.thumbnail.pathComponent)/"
        guard url.host == "cdns.grindr.com", url.path.hasPrefix(thumbnail) else { return nil }
        return String(url.path.dropFirst(thumbnail.count))
    }

    /// `string` as a URL if it is an `https` URL on a host media may come from.
    public static func validated(_ string: String) -> URL? {
        guard let url = URL(string: string), url.scheme == "https", let host = url.host else {
            return nil
        }
        return isAllowed(host: host) ? url : nil
    }

    static func isAllowed(host: String) -> Bool {
        allowedHosts.contains(host) || host.hasSuffix(".cloudfront.net")
    }
}
