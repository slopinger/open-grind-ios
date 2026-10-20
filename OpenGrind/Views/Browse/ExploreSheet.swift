import MapKit
import OpenGrindKit
import SwiftUI

/// A map for choosing a place to look around: search for a city, tap the map
/// or drag the pin, then explore. Your own location stays where it is.
struct ExploreSheet: View {
    /// Where the pin starts: the place you are exploring, or where you are.
    let start: ExplorePlace?
    let isExploring: Bool
    let explore: (ExplorePlace?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    @State private var pin: CLLocationCoordinate2D?
    @State private var placeName: String?
    @State private var isDragging = false
    /// From the pin's tip to the finger, so the pin doesn't jump under it.
    @State private var dragOffset: CGSize?
    /// The pin position `placeName` came from a search for; not looked up again.
    @State private var namedPin: PinKey?
    @State private var query = ""
    @State private var results: [PlaceResult] = []
    /// Where the camera is, to search near it.
    @State private var visibleRegion: MKCoordinateRegion?

    init(start: ExplorePlace?, isExploring: Bool, explore: @escaping (ExplorePlace?) -> Void) {
        self.start = start
        self.isExploring = isExploring
        self.explore = explore
        let coordinate = start.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        _pin = State(initialValue: coordinate)
        _placeName = State(initialValue: isExploring ? start?.name : nil)
        _namedPin = State(initialValue: isExploring && start?.name != nil ? coordinate.map(PinKey.init) : nil)
        _position = State(
            initialValue: coordinate.map {
                MapCameraPosition.region(
                    MKCoordinateRegion(center: $0, latitudinalMeters: 20_000, longitudinalMeters: 20_000))
            } ?? .automatic)
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()
                    if let pin {
                        Annotation("Explore Here", coordinate: pin, anchor: .bottom) {
                            PinView(isLifted: isDragging)
                                .gesture(
                                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                        .onChanged { value in
                                            let offset = dragOffset ?? tipOffset(proxy, from: value.startLocation)
                                            dragOffset = offset
                                            isDragging = true
                                            let point = CGPoint(
                                                x: value.location.x + offset.width,
                                                y: value.location.y + offset.height)
                                            if let coordinate = proxy.convert(point, from: .global) {
                                                self.pin = coordinate
                                            }
                                        }
                                        .onEnded { _ in
                                            dragOffset = nil
                                            isDragging = false
                                        }
                                )
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
                .onTapGesture { point in
                    if let coordinate = proxy.convert(point, from: .local) { pin = coordinate }
                }
                .onMapCameraChange(frequency: .onEnd) { visibleRegion = $0.region }
            }
            .safeAreaInset(edge: .bottom) { panel }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for a City"
            )
            .searchSuggestions {
                ForEach(results) { result in
                    Button {
                        select(result)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(result.name)
                                .foregroundStyle(.primary)
                            if let subtitle = result.subtitle {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .onSubmit(of: .search) {
                if let first = results.first { select(first) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: query) {
                guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                    results = []
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                results = await PlaceLookup.search(query, near: visibleRegion)
            }
            // Looks the name up once the pin rests.
            .task(id: isDragging ? nil : pin.map(PinKey.init)) {
                guard let pin, !isDragging, PinKey(pin) != namedPin else { return }
                placeName = nil
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                placeName = await PlaceLookup.name(at: pin)
            }
            .sensoryFeedback(.selection, trigger: isDragging) { _, new in new }
        }
    }

    private var panel: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                if let pin {
                    Text(placeName ?? String(localized: "Selected Place"))
                        .font(.headline)
                        .lineLimit(1)
                    Text(Self.coordinates(pin))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("Tap the Map to Choose a Place")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            Button {
                guard let pin else { return }
                explore(ExplorePlace(latitude: pin.latitude, longitude: pin.longitude, name: placeName))
                dismiss()
            } label: {
                Label("Explore Here", systemImage: "binoculars.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.brandProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(pin == nil)

            if isExploring {
                Button("Back to My Location", systemImage: "location.fill") {
                    explore(nil)
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
            }

            Text("Drag the pin or tap the map to move it. Your profile stays where you are.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.bar)
    }

    private func select(_ result: PlaceResult) {
        let coordinate = CLLocationCoordinate2D(latitude: result.latitude, longitude: result.longitude)
        pin = coordinate
        placeName = result.name
        namedPin = PinKey(coordinate)
        query = ""
        results = []
        withAnimation {
            position = .region(
                MKCoordinateRegion(center: coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000))
        }
    }

    private func tipOffset(_ proxy: MapProxy, from start: CGPoint) -> CGSize {
        guard let pin, let tip = proxy.convert(pin, to: .global) else { return .zero }
        return CGSize(width: tip.x - start.x, height: tip.y - start.y)
    }

    private static func coordinates(_ coordinate: CLLocationCoordinate2D) -> String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(3))
        return "\(coordinate.latitude.formatted(format)), \(coordinate.longitude.formatted(format))"
    }
}

/// The pin you move around; lifts while you drag it.
private struct PinView: View {
    let isLifted: Bool

    var body: some View {
        VStack(spacing: -4) {
            Image(systemName: "binoculars.circle.fill")
                .font(.system(size: 38))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.brandForeground, Color.brand)
                .background(Circle().fill(.white).padding(2))
            Image(systemName: "triangle.fill")
                .font(.system(size: 12))
                .rotationEffect(.degrees(180))
                .foregroundStyle(Color.brand)
        }
        .shadow(color: .black.opacity(0.3), radius: isLifted ? 8 : 2, y: isLifted ? 6 : 1)
        .scaleEffect(isLifted ? 1.15 : 1, anchor: .bottom)
        .offset(y: isLifted ? -8 : 0)
        .animation(.spring(duration: 0.25), value: isLifted)
        .contentShape(.rect)
        .accessibilityHidden(true)
    }
}

/// Changes when the pin moves by more than about 10 m, so tiny moves don't look up a name.
private struct PinKey: Hashable {
    var latitude: Int
    var longitude: Int

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = Int((coordinate.latitude * 10_000).rounded())
        longitude = Int((coordinate.longitude * 10_000).rounded())
    }
}

/// A place found by searching.
struct PlaceResult: Identifiable, Hashable, Sendable {
    var name: String
    var subtitle: String?
    var latitude: Double
    var longitude: Double

    var id: String { "\(name)|\(latitude)|\(longitude)" }
}

/// Place search and names, through Apple Maps.
enum PlaceLookup {
    /// Cities and addresses matching `query`, preferring ones near `region`.
    @concurrent
    static func search(_ query: String, near region: MKCoordinateRegion?) async -> [PlaceResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        if let region { request.region = region }
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.prefix(8).compactMap { item in
            let placemark = item.placemark
            guard let name = item.name ?? placemark.locality else { return nil }
            let parts = [placemark.locality, placemark.administrativeArea, placemark.country]
                .compactMap { $0 }
                .filter { $0 != name }
            return PlaceResult(
                name: name, subtitle: parts.isEmpty ? nil : parts.joined(separator: ", "),
                latitude: placemark.coordinate.latitude, longitude: placemark.coordinate.longitude)
        }
    }

    /// A short name for the area around `coordinate`, such as "Kreuzberg, Berlin".
    @concurrent
    static func name(at coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let parts = [placemark.subLocality, placemark.locality ?? placemark.administrativeArea]
            .compactMap { $0 }
        if parts.isEmpty { return placemark.country ?? placemark.ocean }
        return parts.joined(separator: ", ")
    }
}
