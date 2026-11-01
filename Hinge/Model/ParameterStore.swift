import Combine
import Foundation

/// Owns the live `EffectParameters` and persists them to `UserDefaults` under a
/// single key. Undecodable data falls back to defaults rather than crashing.
final class ParameterStore: ObservableObject {
    static let defaultsKey = "effectParameters.v1"

    @Published var params: EffectParameters {
        didSet {
            // Assigning inside didSet does not re-trigger observers.
            let fixed = params.clamped()
            if fixed != params { params = fixed }
            if params != oldValue { save() }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.params = Self.load(from: defaults)
    }

    func resetToDefaults() {
        params = .defaults
    }

    static func load(from defaults: UserDefaults) -> EffectParameters {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(EffectParameters.self, from: data) else {
            return .defaults
        }
        return decoded.clamped()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(params) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
