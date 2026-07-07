import Foundation

/// The user's chosen dashboard companion. This is *identity* — persisted and
/// stable across launches, navigation, and document opens. It is deliberately
/// kept separate from the pet's transient animation/behaviour state (which lives
/// in `PetBuddy`: current message, bounce, bubble visibility), so switching pages
/// or reloading never resets the selected animal.
enum PetSpecies: String, CaseIterable, Sendable {
    case dog
    case cat

    /// The companion shown when the user hasn't chosen yet or a stored value is
    /// missing/corrupt. Dog is the friendly default.
    static let fallback: PetSpecies = .dog

    /// Lenient parse used everywhere identity is read from storage, so a garbage
    /// or absent value can never crash or blank the pet.
    static func resolved(from raw: String?) -> PetSpecies {
        raw.flatMap(PetSpecies.init(rawValue:)) ?? .fallback
    }

    /// Localized display name ("Dog" / "Cat").
    var displayName: String {
        switch self {
        case .dog: return L10n.string("pet.species.dog.name")
        case .cat: return L10n.string("pet.species.cat.name")
        }
    }

    /// One-line personality tagline for the picker cards.
    var tagline: String {
        switch self {
        case .dog: return L10n.string("pet.species.dog.tagline")
        case .cat: return L10n.string("pet.species.cat.tagline")
        }
    }

    /// SF Symbol used as a small badge / reduce-motion resting glyph. These ship
    /// with macOS 14 (the deployment target).
    var symbolName: String {
        switch self {
        case .dog: return "dog.fill"
        case .cat: return "cat.fill"
        }
    }

    var accessibilityLabel: String { displayName }

    /// Species-flavored greeting shown on the intro page once a companion is chosen.
    /// Keys are literals (see `PetLines.speciesHero` for why interpolation is unsafe).
    var introGreeting: String {
        switch self {
        case .dog: return L10n.string("gami.intro.greeting")
        case .cat: return L10n.string("pet.cat.intro.greeting")
        }
    }

    var introMessage: String {
        switch self {
        case .dog: return L10n.string("gami.intro.message")
        case .cat: return L10n.string("pet.cat.intro.message")
        }
    }
}
