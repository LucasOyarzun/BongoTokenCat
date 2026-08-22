import Foundation

@MainActor
func runAllTests() -> Never {
    runEventMappingTests()
    runStateDecayTests()
    runGitContextTests()
    runDrumEngineTests()
    runPawPositionTests()
    runAgentRegistryTests()
    runSkinCatalogTests()
    runOverlayLayoutTests()
    runTokenReaderTests()
    runTokenReaderPerformanceTests()
    runUsageCacheTests()
    runOverlayInteractionTests()
    reportAndExit()
}

MainActor.assumeIsolated { runAllTests() }
