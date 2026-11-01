import XCTest

final class AngleProcessorTests: XCTestCase {
    func testFirstSampleInitialises() {
        var p = AngleProcessor(smoothingMs: 80)
        XCTAssertEqual(p.step(input: 120, dt: 0), 120)
    }

    func testConstantInputStaysConstant() {
        var p = AngleProcessor(smoothingMs: 80)
        p.reset(to: 100)
        for _ in 0..<600 {
            XCTAssertEqual(p.step(input: 100, dt: 1.0 / 60), 100)
        }
    }

    func testStepConvergesWithinThreeTimeConstants() {
        let ms = 80.0
        var p = AngleProcessor(smoothingMs: ms)
        p.reset(to: 120)
        var t = 0.0
        let dt = 1.0 / 60
        while t < 3 * ms / 1000 {
            p.step(input: 20, dt: dt)
            t += dt
        }
        XCTAssertEqual(p.output!, 20, accuracy: 0.1)
        // And it is still most of the way there after one time constant.
        var q = AngleProcessor(smoothingMs: ms)
        q.reset(to: 120)
        q.step(input: 20, dt: ms / 1000)
        XCTAssertLessThan(q.output!, 30)
        XCTAssertGreaterThan(q.output!, 20)
    }

    func testNoOvershoot() {
        var p = AngleProcessor(smoothingMs: 80)
        p.reset(to: 120)
        for _ in 0..<240 {
            XCTAssertGreaterThanOrEqual(p.step(input: 20, dt: 1.0 / 120), 20 - 1e-9)
        }
    }

    func testJitterInsideDeadbandIsIgnored() {
        var p = AngleProcessor(smoothingMs: 80, deadband: 0.3)
        p.reset(to: 100)
        let jitter = [0.1, -0.2, 0.29, -0.29, 0.0, 0.15]
        for j in jitter {
            XCTAssertEqual(p.step(input: 100 + j, dt: 1.0 / 60), 100)
        }
    }

    func testChangeOutsideDeadbandIsFollowed() {
        var p = AngleProcessor(smoothingMs: 80, deadband: 0.3)
        p.reset(to: 100)
        for _ in 0..<60 { p.step(input: 101, dt: 1.0 / 60) }
        XCTAssertEqual(p.output!, 101, accuracy: 1e-3)
    }

    func testFrameRateIndependent() {
        func run(hz: Double) -> [Double] {
            var p = AngleProcessor(smoothingMs: 80)
            p.reset(to: 120)
            let steps = Int(hz) // one second
            var samples: [Double] = []
            let stride = Int(hz / 10)
            for i in 1...steps {
                let input = i <= steps / 2 ? 30.0 : 90.0
                p.step(input: input, dt: 1 / hz)
                if i % stride == 0 { samples.append(p.output!) }
            }
            return samples
        }
        let a = run(hz: 30), b = run(hz: 60), c = run(hz: 120)
        XCTAssertEqual(a.count, 10)
        for i in 0..<a.count {
            XCTAssertEqual(a[i], b[i], accuracy: 1e-6)
            XCTAssertEqual(b[i], c[i], accuracy: 1e-6)
        }
    }

    func testZeroSmoothingPassesThrough() {
        var p = AngleProcessor(smoothingMs: 0)
        p.reset(to: 100)
        XCTAssertEqual(p.step(input: 40, dt: 1.0 / 60), 40)
    }
}
