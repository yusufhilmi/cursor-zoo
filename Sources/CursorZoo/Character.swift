import AppKit

/// Discrete things the pointer can do that a character reacts to.
enum Reaction: Hashable {
    case leftClick
    case rightClick
    case doubleClick
    case scroll
}

struct Character {
    let id: String
    let name: String
    /// Menu-bar icon only. The character itself is a vector rig.
    let glyph: String
    /// Optional speech bubbles, off by default; see the menu.
    let bubbles: [Reaction: String]
    let makeRig: () -> CharacterRig

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
        bubbles: [.leftClick: "squeak!", .rightClick: "eek!", .doubleClick: "thwack!"],
        makeRig: { MouseRig() }
    )

    /// Original top-down racer. Front bumper is the pointer.
    static let lilRacer = Character(
        id: "lil-racer",
        name: "Lil Racer",
        glyph: "🏎️",
        bubbles: [.leftClick: "BEEP!", .rightClick: "skrrt!", .doubleClick: "NITRO!"],
        makeRig: { RacerRig() }
    )

    /// Original chibi ninja in shadow black. The point of the hood is the pointer.
    static let shadowNinja = Character(
        id: "shadow-ninja",
        name: "Shadow Ninja",
        glyph: "🥷",
        bubbles: [.leftClick: "POW!", .rightClick: "BAM!", .doubleClick: "HIYAA!"],
        makeRig: { NinjaRig() }
    )

    /// Original chibi dragon. The snout is the pointer.
    static let pocketDragon = Character(
        id: "pocket-dragon",
        name: "Pocket Dragon",
        glyph: "🐉",
        bubbles: [.leftClick: "chomp!", .rightClick: "whoosh!", .doubleClick: "FIRE!"],
        makeRig: { DragonRig() }
    )
}

/// Overall sprite scale, mirroring the S / M / L control in the Polymet playground.
enum CharacterSize: String, CaseIterable {
    case small, medium, large

    var points: CGFloat {
        switch self {
        case .small: return 26
        case .medium: return 34
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
