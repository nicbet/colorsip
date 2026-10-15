/// The short sounds that confirm picks and copies (`spec.md` §4.5, §3.1).
public enum SoundEffect: Sendable, CaseIterable {
    /// A pick that keeps the picker open (Shift+click, multi mode).
    case pick
    /// A pick that closes the picker.
    case slurp
    /// A swatch copied: click, or Copy as….
    case plopp

    /// The `.wav` file in the app bundle.
    public var resourceName: String {
        switch self {
        case .pick: "pick-color"
        case .slurp: "zeeoup"
        case .plopp: "plopp"
        }
    }

    /// The sound a picker step makes, if any: closing or choosing a mode is silent.
    public static func forStep(_ step: PickerStep) -> SoundEffect? {
        switch step {
        case .pick(_, let close, _): close ? .slurp : .pick
        case .close, .none: nil
        }
    }
}

/// Plays sounds: `NSSound` in the app, a fake in tests.
@MainActor
public protocol SoundPlayer {
    func play(_ effect: SoundEffect)
}

/// Plays sound effects unless Settings ▸ General turned them off.
@MainActor
public final class SoundEffects {
    private let player: any SoundPlayer
    private let settings: SettingsStore

    public init(player: any SoundPlayer, settings: SettingsStore) {
        self.player = player
        self.settings = settings
    }

    public func play(_ effect: SoundEffect) {
        guard settings.settings.soundEffects else { return }
        player.play(effect)
    }

    public func play(for step: PickerStep) {
        SoundEffect.forStep(step).map(play)
    }
}
