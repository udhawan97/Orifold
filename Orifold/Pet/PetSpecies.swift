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
    func displayName(locale: Locale) -> String {
        switch self {
        case .dog: return L10n.string("pet.species.dog.name", locale: locale)
        case .cat: return L10n.string("pet.species.cat.name", locale: locale)
        }
    }

    /// One-line personality tagline for the picker cards.
    func tagline(locale: Locale) -> String {
        switch self {
        case .dog: return L10n.string("pet.species.dog.tagline", locale: locale)
        case .cat: return L10n.string("pet.species.cat.tagline", locale: locale)
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

    func accessibilityLabel(locale: Locale) -> String { displayName(locale: locale) }

    /// Species-flavored greeting shown on the intro page once a companion is chosen.
    /// Keys are literals (see `PetLines.speciesHero` for why interpolation is unsafe).
    func introGreeting(locale: Locale) -> String {
        switch self {
        case .dog: return L10n.string("gami.intro.greeting", locale: locale)
        case .cat: return L10n.string("pet.cat.intro.greeting", locale: locale)
        }
    }

    func introMessage(locale: Locale) -> String {
        switch self {
        case .dog: return L10n.string("gami.intro.message", locale: locale)
        case .cat: return L10n.string("pet.cat.intro.message", locale: locale)
        }
    }
}
