import XCTest

final class EffectModelTests: XCTestCase {
    let params = EffectParameters.defaults // 105° → 25°

    func testInactiveAtAndAboveActivation() {
        for θ in [105.0, 106, 120, 180] {
            let s = EffectModel.evaluate(angle: θ, params: params)
            XCTAssertEqual(s.p, 0)
            XCTAssertFalse(s.isActive)
            XCTAssertEqual(s, .inactive)
        }
    }

    func testFullAtAndBelowFullStrength() {
        for θ in [25.0, 24, 10, 0] {
            let s = EffectModel.evaluate(angle: θ, params: params)
            XCTAssertEqual(s.p, 1)
            XCTAssertEqual(s.e, 1, accuracy: 1e-12)
        }
    }

    func testMonotonicBetween() {
        for curve in EaseCurve.allCases {
            var p = params
            p.easeCurve = curve
            var last = -1.0
            var lastE = -1.0
            for θ in stride(from: 105.0, through: 25.0, by: -0.5) {
                let s = EffectModel.evaluate(angle: θ, params: p)
                XCTAssertGreaterThanOrEqual(s.p, last)
                XCTAssertGreaterThanOrEqual(s.e, lastE)
                last = s.p
                lastE = s.e
            }
        }
    }

    func testProgressMidpointIsLinear() {
        XCTAssertEqual(EffectModel.progress(angle: 65, params: params), 0.5, accuracy: 1e-12)
    }

    func testEaseCurveEndpoints() {
        for curve in EaseCurve.allCases {
            XCTAssertEqual(curve.apply(0), 0, accuracy: 1e-12, "\(curve)")
            XCTAssertEqual(curve.apply(1), 1, accuracy: 1e-12, "\(curve)")
            XCTAssertEqual(curve.apply(-1), 0, accuracy: 1e-12, "\(curve)")
            XCTAssertEqual(curve.apply(2), 1, accuracy: 1e-12, "\(curve)")
        }
        XCTAssertEqual(EaseCurve.smoothstep.apply(0.5), 0.5, accuracy: 1e-12)
        XCTAssertGreaterThan(EaseCurve.easeOut.apply(0.5), 0.5)
    }

    func testBrightnessFormula() {
        var p = params
        p.easeCurve = .linear
        p.maxDim = 0.8
        let s = EffectModel.evaluate(angle: 65, params: p) // p = 0.5
        XCTAssertEqual(s.brightness, 1 - 0.5 * 0.8, accuracy: 1e-12)
        XCTAssertEqual(EffectModel.evaluate(angle: 0, params: p).brightness, 0.2, accuracy: 1e-12)
    }

    func testBlurFormula() {
        var p = params
        p.easeCurve = .linear
        p.maxBlur = 40
        p.blurGamma = 2
        let s = EffectModel.evaluate(angle: 65, params: p) // e = 0.5
        XCTAssertEqual(s.blurAt(0), 0, accuracy: 1e-12)
        XCTAssertEqual(s.blurAt(1), 20, accuracy: 1e-12)
        XCTAssertEqual(s.blurAt(0.5), 0.5 * 40 * 0.25, accuracy: 1e-12)
        XCTAssertLessThan(s.blurAt(0.3), s.blurAt(0.7))
    }

    func testLeanDirectionFlipsOnlyLean() {
        var a = params
        a.leanDirection = 1
        var b = params
        b.leanDirection = -1
        let sa = EffectModel.evaluate(angle: 50, params: a)
        let sb = EffectModel.evaluate(angle: 50, params: b)
        XCTAssertGreaterThan(sa.leanRadians, 0)
        XCTAssertEqual(sa.leanRadians, -sb.leanRadians, accuracy: 1e-12)
        var sbFlipped = sb
        sbFlipped.leanRadians = sa.leanRadians
        XCTAssertEqual(sa, sbFlipped)
    }

    func testLeanAtFullStrength() {
        let s = EffectModel.evaluate(angle: 0, params: params)
        XCTAssertEqual(s.leanRadians, 50 * .pi / 180, accuracy: 1e-12)
    }

    func testDisabledIsInactive() {
        var p = params
        p.enabled = false
        XCTAssertEqual(EffectModel.evaluate(angle: 0, params: p), .inactive)
    }

    func testDegenerateRangeDoesNotDivideByZero() {
        var p = params
        p.fullStrengthAngle = p.activationAngle // bypass clamped()
        XCTAssertEqual(EffectModel.progress(angle: 104, params: p), 1)
        XCTAssertEqual(EffectModel.progress(angle: 106, params: p), 0)
    }
}

final class EffectParametersTests: XCTestCase {
    func testClampKeepsFullStrengthBelowActivation() {
        var p = EffectParameters()
        p.activationAngle = 50
        p.fullStrengthAngle = 80
        let c = p.clamped()
        XCTAssertLessThan(c.fullStrengthAngle, c.activationAngle)
        XCTAssertEqual(c.activationAngle, 50)
    }

    func testClampRanges() {
        var p = EffectParameters()
        p.maxDim = 3
        p.blurGamma = 0
        p.leanDirection = -7
        p.activationAngle = 500
        let c = p.clamped()
        XCTAssertEqual(c.maxDim, 1)
        XCTAssertEqual(c.blurGamma, 0.5)
        XCTAssertEqual(c.leanDirection, -1)
        XCTAssertEqual(c.activationAngle, 150)
    }

    func testRoundTrip() throws {
        var p = EffectParameters()
        p.maxBlur = 12
        p.easeCurve = .easeOut
        p.leanDirection = -1
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(EffectParameters.self, from: data), p)
    }

    func testPartialAndCorruptDecodeFallsBackPerKey() throws {
        let json = #"{"maxBlur": 9, "easeCurve": "bogus", "maxDim": "nope"}"#
        let p = try JSONDecoder().decode(EffectParameters.self, from: Data(json.utf8))
        XCTAssertEqual(p.maxBlur, 9)
        XCTAssertEqual(p.easeCurve, EffectParameters.defaults.easeCurve)
        XCTAssertEqual(p.maxDim, EffectParameters.defaults.maxDim)
        XCTAssertEqual(p.activationAngle, EffectParameters.defaults.activationAngle)
    }

    func testStorePersistsAndSurvivesGarbage() {
        let suite = "hinge.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ParameterStore(defaults: defaults)
        XCTAssertEqual(store.params, .defaults)
        store.params.maxBlur = 33
        XCTAssertEqual(ParameterStore(defaults: defaults).params.maxBlur, 33)

        defaults.set(Data([0xde, 0xad]), forKey: ParameterStore.defaultsKey)
        XCTAssertEqual(ParameterStore(defaults: defaults).params, .defaults)
    }

    func testStoreClampsOnAssignment() {
        let suite = "hinge.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ParameterStore(defaults: defaults)
        store.params.fullStrengthAngle = 200
        XCTAssertLessThan(store.params.fullStrengthAngle, store.params.activationAngle)
    }
}

final class PollingPolicyTests: XCTestCase {
    func testRates() {
        let p = EffectParameters.defaults // activation 105
        XCTAssertEqual(PollingPolicy.rate(angle: 130, params: p), PollingPolicy.idleHz)
        XCTAssertEqual(PollingPolicy.rate(angle: 120, params: p), PollingPolicy.approachHz)
        XCTAssertEqual(PollingPolicy.rate(angle: 111, params: p), PollingPolicy.approachHz)
        XCTAssertEqual(PollingPolicy.rate(angle: 110, params: p), PollingPolicy.activeHz)
        XCTAssertEqual(PollingPolicy.rate(angle: 60, params: p), PollingPolicy.activeHz)
        XCTAssertEqual(PollingPolicy.rate(angle: nil, params: p), PollingPolicy.idleHz)
        var off = p
        off.enabled = false
        XCTAssertEqual(PollingPolicy.rate(angle: 60, params: off), 0)
        off.showAngleInMenuBar = true
        XCTAssertEqual(PollingPolicy.rate(angle: 60, params: off), PollingPolicy.idleHz)
    }

    func testHysteresisAtBoundaries() {
        let p = EffectParameters.defaults // 60 Hz ≤ 110, 15 Hz ≤ 120, else 4 Hz
        let fast = PollingPolicy.activeHz, mid = PollingPolicy.approachHz, slow = PollingPolicy.idleHz
        // Speeding up is immediate.
        XCTAssertEqual(PollingPolicy.rate(angle: 121, params: p, current: slow), slow)
        XCTAssertEqual(PollingPolicy.rate(angle: 120, params: p, current: slow), mid)
        XCTAssertEqual(PollingPolicy.rate(angle: 110, params: p, current: mid), fast)
        XCTAssertEqual(PollingPolicy.rate(angle: 90, params: p, current: slow), fast)
        // Jitter just above a boundary keeps the faster tier…
        XCTAssertEqual(PollingPolicy.rate(angle: 121, params: p, current: mid), mid)
        XCTAssertEqual(PollingPolicy.rate(angle: 123, params: p, current: mid), mid)
        XCTAssertEqual(PollingPolicy.rate(angle: 113, params: p, current: fast), fast)
        // …until it clearly leaves.
        XCTAssertEqual(PollingPolicy.rate(angle: 124, params: p, current: mid), slow)
        XCTAssertEqual(PollingPolicy.rate(angle: 114, params: p, current: fast), mid)
        XCTAssertEqual(PollingPolicy.rate(angle: 130, params: p, current: fast), slow)
    }
}
