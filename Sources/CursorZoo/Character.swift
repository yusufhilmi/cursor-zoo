import AppKit

/// Discrete things the pointer can do that a character reacts to.
enum Reaction: Hashable {
    case leftClick
    case rightClick
    case doubleClick
    case scroll
}

/// How a character physically responds to a reaction. Pure motion — no art needed.
enum Move {
    case squish      // flatten into the click
    case recoil      // kick back the other way
    case hop         // arc up and land
    case spin        // rotate (driven by scroll delta)
}

struct Character {
    let id: String
    let name: String
    /// Placeholder art. Swapped for real sprites from the Polymet pack later.
    let glyph: String
    /// Where the character sits relative to the real pointer, in points.
    /// The system cursor stays visible in companion mode, so we sit just off its tip.
    let offset: CGSize
    /// Resting rotation, radians. Lets wheels/blades sit at a natural angle.
    let restAngle: CGFloat
    /// How hard the character leans into its direction of travel. 0 = rigid.
    let lean: CGFloat
    let moves: [Reaction: Move]
    let bubbles: [Reaction: String]

    func move(for r: Reaction) -> Move? { moves[r] }
    func bubble(for r: Reaction) -> String? { bubbles[r] }
}

extension Character {
    static let all: [Character] = [tinyMouse, lilRacer, shadowNinja, pocketDragon]

    static func named(_ id: String) -> Character {
        all.first { $0.id == id } ?? tinyMouse
    }

    /// The one Cey built in Polymet. Nose is the pointer tip.
    static let tinyMouse = Character(
        id: "tiny-mouse",
        name: "Tiny Mouse",
        glyph: "🐭",
        offset: CGSize(width: 13, height: -13),
        restAngle: 0,
        lean: 0.9,
        moves: [.leftClick: .squish, .rightClick: .recoil, .doubleClick: .hop, .scroll: .spin],
        bubbles: [.leftClick: "squeak!", .rightClick: "big backs!", .doubleClick: "thwack!", .scroll: "scurry"]
    )

    /// Original little racer — wheels turn with the scroll wheel. Not anyone's IP.
    static let lilRacer = Character(
        id: "lil-racer",
        name: "Lil Racer",
        glyph: "🏎️",
        offset: CGSize(width: 16, height: -12),
        restAngle: 0,
        lean: 1.4,
        moves: [.leftClick: .recoil, .rightClick: .recoil, .doubleClick: .hop, .scroll: .spin],
        bubbles: [.leftClick: "vroom", .rightClick: "skrrt", .doubleClick: "NITRO!", .scroll: "brrrr"]
    )

    /// Original anime-style fighter. Left punch, right kick.
    static let shadowNinja = Character(
        id: "shadow-ninja",
        name: "Shadow Ninja",
        glyph: "🥷",
        offset: CGSize(width: 14, height: -14),
        restAngle: 0,
        lean: 0.7,
        moves: [.leftClick: .squish, .rightClick: .recoil, .doubleClick: .hop, .scroll: .spin],
        bubbles: [.leftClick: "PUNCH", .rightClick: "KICK", .doubleClick: "ULTIMATE!!", .scroll: "whoosh"]
    )

    static let pocketDragon = Character(
        id: "pocket-dragon",
        name: "Pocket Dragon",
        glyph: "🐉",
        offset: CGSize(width: 15, height: -14),
        restAngle: 0,
        lean: 1.1,
        moves: [.leftClick: .squish, .rightClick: .recoil, .doubleClick: .hop, .scroll: .spin],
        bubbles: [.leftClick: "rawr", .rightClick: "hmph", .doubleClick: "FIRE!", .scroll: "flap flap"]
    )
}

/// Overall sprite scale, mirroring the S / M / L control in the Polymet playground.
enum CharacterSize: String, CaseIterable {
    case small, medium, large

    var points: CGFloat {
        switch self {
        case .small: return 22
        case .medium: return 32
        case .large: return 46
        }
    }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}
