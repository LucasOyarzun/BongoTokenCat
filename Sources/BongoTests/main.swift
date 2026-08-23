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
    runOverlayInteractionTests()
    await runHookServerTests()
    reportAndExit()
}

await runAllTests()
