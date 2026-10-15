import AppKit
import ColorsipCore

/// Plays the bundled `Sounds/*.wav` files. Each effect keeps one `NSSound`, loaded on first use;
/// playing it again restarts it, so rapid repeats don't pile up.
@MainActor
final class NSSoundPlayer: SoundPlayer {
    private var sounds: [SoundEffect: NSSound] = [:]

    func play(_ effect: SoundEffect) {
        guard let sound = sound(for: effect) else { return }
        sound.stop()
        sound.play()
    }

    private func sound(for effect: SoundEffect) -> NSSound? {
        if let sound = sounds[effect] { return sound }
        guard let url = Bundle.main.url(forResource: effect.resourceName, withExtension: "wav"),
            let sound = NSSound(contentsOf: url, byReference: true)
        else { return nil }
        sounds[effect] = sound
        return sound
    }
}
