import XCTest

/// Seeded model-based exploratory runs. Short one lives in the fast suite; the long, configurable
/// one lives in the stress suite. Both are exactly replayable from their seed.
final class ExplorerSmokeTests: LuminaUITestCase {
    func testShortSeededExplorer() {
        let seed: UInt64 = TestEnv.seed ?? 84_721
        launch(LaunchConfig(fixture: .mixed60, seed: seed))
        let runner = ExplorerRunner(test: self, fixture: .mixed60, seed: seed, steps: 25)
        runner.run(steps: 25)
    }
}

final class ExplorerStressTests: LuminaUITestCase {
    func testLongSeededExplorer() {
        let seed: UInt64 = TestEnv.seed ?? 84_721
        let steps = TestEnv.steps ?? 200
        launch(LaunchConfig(fixture: .mixed200, seed: seed))
        let runner = ExplorerRunner(test: self, fixture: .mixed200, seed: seed, steps: steps)
        runner.run(steps: steps)
    }
}
