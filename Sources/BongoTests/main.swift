import Foundation

@MainActor
func runAllTests() async -> Never {
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
    await runHookServerTests()
    reportAndExit()
}

await runAllTests()
