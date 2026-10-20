import OpenGrindKit
import SwiftUI

/// Name, presence and every detail a profile shares, in sections.
struct ProfileDetails: View {
    let profile: Profile
    let me: MeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            if let about = profile.aboutMe, !about.isEmpty {
                Text(about)
                    .textSelection(.enabled)
            }
            if !profile.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(profile.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.fill.secondary, in: .capsule)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Tags: \(profile.tags.formatted(.list(type: .and)))")
            }
            DetailSection("Stats", rows: stats)
            DetailSection("Identity", rows: identity)
            DetailSection("Expectations", rows: expectations)
            DetailSection("Sexual Health", rows: health)
            if let instagram = profile.instagram, !instagram.isEmpty,
                let url = URL(string: "https://instagram.com/\(instagram)")
            {
                Link(destination: url) {
                    Label("@\(instagram) on Instagram", systemImage: "camera")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(profile.displayName ?? String(localized: "No name"))
                    .font(.title.bold())
                if profile.showsAge, let age = profile.age {
                    Text(age, format: .number)
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                if let presence = Formatting.presence(
                    onlineUntil: profile.onlineUntil, lastSeen: profile.lastSeen)
                {
                    HStack(spacing: 5) {
                        if profile.isOnline() {
                            OnlineIndicator().frame(width: 9, height: 9)
                        }
                        Text(presence)
                    }
                }
                if profile.showsDistance,
                    let distance = Formatting.distance(
                        profile.distance, approximate: profile.isDistanceApproximate)
                {
                    Label(distance, systemImage: "location.fill")
                        .labelStyle(.titleAndIcon)
                }
                if profile.isVisiting || profile.isRoaming {
                    Label("Visiting", systemImage: "airplane")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let tap = profile.receivedTap {
                Text("\(tap.emoji) Sent you a \(tap.localizedName) tap")
                    .font(.subheadline.weight(.medium))
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var stats: [DetailRow] {
        [
            DetailRow("Height", profile.height.map(Formatting.height)),
            DetailRow("Weight", profile.weight.map(Formatting.weight)),
            DetailRow("Body Type", profile.bodyType?.localizedName),
            DetailRow("Position", profile.showsPosition ? profile.position?.localizedName : nil),
            DetailRow("Ethnicity", profile.ethnicity?.localizedName),
            DetailRow("Relationship", profile.relationshipStatus?.localizedName),
        ]
    }

    private var identity: [DetailRow] {
        let genders = profile.genderIDs.compactMap { me.gender($0)?.name }
        let pronouns = profile.pronounIDs.compactMap { me.pronoun($0)?.name }
        return [
            DetailRow("Gender", genders.isEmpty ? nil : genders.formatted(.list(type: .and))),
            DetailRow("Pronouns", pronouns.isEmpty ? nil : pronouns.joined(separator: ", ")),
            DetailRow(
                "Tribes",
                profile.showsTribes && !profile.tribes.isEmpty ? profile.tribes.localizedList : nil),
        ]
    }

    private var expectations: [DetailRow] {
        [
            DetailRow("Looking For", profile.lookingFor.isEmpty ? nil : profile.lookingFor.localizedList),
            DetailRow("Meet At", profile.meetAt.isEmpty ? nil : profile.meetAt.localizedList),
            DetailRow("NSFW Pics", profile.acceptsNSFWPics?.localizedName),
        ]
    }

    private var health: [DetailRow] {
        [
            DetailRow("HIV Status", profile.hivStatus?.localizedName),
            DetailRow("Last Tested", profile.lastTested?.formatted(.dateTime.month(.wide).year())),
            DetailRow(
                "Practices", profile.sexualHealth.isEmpty ? nil : profile.sexualHealth.localizedList),
            DetailRow("Vaccinated", profile.vaccines.isEmpty ? nil : profile.vaccines.localizedList),
        ]
    }
}

/// One labeled value of a profile.
struct DetailRow: Identifiable {
    let title: LocalizedStringKey
    let value: String?
    let id = UUID()

    init(_ title: LocalizedStringKey, _ value: String?) {
        self.title = title
        self.value = value
    }
}

/// A titled group of profile details; hidden when the profile shares none of them.
struct DetailSection: View {
    let title: LocalizedStringKey
    let rows: [DetailRow]

    init(_ title: LocalizedStringKey, rows: [DetailRow]) {
        self.title = title
        self.rows = rows.filter { $0.value?.isEmpty == false }
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        LabeledContent(row.title) {
                            Text(row.value ?? "")
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 11)
                        .padding(.horizontal, 16)
                        if row.id != rows.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(.background.secondary, in: .rect(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

/// Lays out views in rows, wrapping like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                let y = row.y + row.height + spacing
                rows.append(row)
                row = Row(y: y)
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
