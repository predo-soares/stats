import Foundation

@MainActor
struct AppDependencies {
    let usageStore: UsageStore

    static func live() -> AppDependencies {
        let pricingCatalog = PricingCatalogStore().load() ?? PricingCatalog(revision: "unpriced", rates: [:])
        let ledger: CodexUsageLedger?
        do {
            ledger = try CodexUsageLedger()
        } catch {
            ledger = nil
        }

        let store = UsageStore(
            ledger: ledger,
            codexService: CodexUsageService(
                importer: CodexUsageImporter(),
                quotaClient: CodexQuotaClient(
                    credentialReader: LocalCodexCredentialReader(),
                    transport: ChatGPTCodexQuotaTransport()
                )
            ),
            cursorService: CursorUsageService(),
            claudeService: ClaudeUsageService(),
            piService: PiUsageService(),
            periodService: UsagePeriodService(pricingCatalog: pricingCatalog)
        )
        return AppDependencies(usageStore: store)
    }
}
