import Foundation

@MainActor
func runAllTests() async -> Never {
    runEventMappingTests()
    runStateDecayTests()
    runGitContextTests()
    runDrumEngineTests()
    runPawPositionTests()
    runAgentRegistryTests()
    runInstrumentCatalogTests()
    runCoatShopTests()
    runOverlayLayoutTests()
    runTokenReaderTests()
    runTokenReaderPerformanceTests()
    runUsageCacheTests()
    runUsageLimitsTests()
    runOverlayInteractionTests()
    await runHookServerTests()
    reportAndExit()
}

await runAllTests()
