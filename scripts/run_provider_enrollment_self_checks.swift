import Foundation

@main
struct RunProviderEnrollmentSelfChecks {
    static func main() {
        var failures: [String] = []
        checkSupportStateSemantics(&failures)
        checkEnrollmentPersistence(&failures)
        checkSkipSelectsNone(&failures)
        checkLegacyMigration(&failures)
        checkCatalogDescriptors(&failures)
        checkPrivacyLivesOnIdentity(&failures)

        if failures.isEmpty {
            print("PASS: provider enrollment lifecycle checks")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func checkSupportStateSemantics(_ failures: inout [String]) {
        guard !ProviderSupportState.supported.showsStatusIcon else {
            failures.append("Supported must not show a status icon")
            return
        }
        guard ProviderSupportState.experimental.showsStatusIcon,
              ProviderSupportState.detected.showsStatusIcon else {
            failures.append("Experimental and Detected must show status icons")
            return
        }
        guard ProviderSupportState.experimental.statusIconSystemName != ProviderSupportState.detected.statusIconSystemName else {
            failures.append("Experimental and Detected icons must differ")
            return
        }
        guard ProviderSupportState.experimental.tooltip.contains("Fixture"),
              ProviderSupportState.detected.tooltip.contains("local source"),
              ProviderSupportState.supported.tooltip.contains("Reconciled") else {
            failures.append("Tooltip semantics drifted from glossary meanings")
            return
        }
        guard UsageProviderIdentity.codex.supportState == .supported,
              UsageProviderIdentity.cursor.supportState == .supported else {
            failures.append("Codex and Cursor must remain Supported until reconciliation policy changes")
            return
        }
    }

    private static func checkEnrollmentPersistence(_ failures: inout [String]) {
        let suite = "stats.provider-enrollment.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProviderEnrollmentStore(defaults: defaults)
        guard !store.hasCompletedEnrollment else {
            failures.append("Fresh suite should not be completed")
            return
        }
        store.finish(with: [.codex])
        guard store.hasCompletedEnrollment,
              store.isEnabled(.codex),
              !store.isEnabled(.cursor) else {
            failures.append("finish(with:) did not persist selective enrollment")
            return
        }
        let reloaded = ProviderEnrollmentStore(defaults: defaults)
        guard reloaded.hasCompletedEnrollment,
              reloaded.isEnabled(.codex),
              !reloaded.isEnabled(.cursor) else {
            failures.append("Enrollment selection did not survive reload")
            return
        }
    }

    private static func checkSkipSelectsNone(_ failures: inout [String]) {
        let suite = "stats.provider-enrollment.skip.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProviderEnrollmentStore(defaults: defaults)
        store.skipSelectingNone()
        guard store.hasCompletedEnrollment,
              !store.isEnabled(.codex),
              !store.isEnabled(.cursor) else {
            failures.append("Skip must complete enrollment with no providers enabled")
            return
        }
    }

    private static func checkLegacyMigration(_ failures: inout [String]) {
        let suite = "stats.provider-enrollment.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "usage.connection.codex")
        defaults.set(false, forKey: "usage.connection.cursor")
        let store = ProviderEnrollmentStore(defaults: defaults)
        store.migrateLegacyConnectionsIfNeeded(hasPriorUsage: false)
        guard store.hasCompletedEnrollment,
              store.isEnabled(.codex),
              !store.isEnabled(.cursor) else {
            failures.append("Legacy connection keys were not migrated")
            return
        }

        let priorSuite = "stats.provider-enrollment.prior.\(UUID().uuidString)"
        let priorDefaults = UserDefaults(suiteName: priorSuite)!
        defer { priorDefaults.removePersistentDomain(forName: priorSuite) }
        let priorStore = ProviderEnrollmentStore(defaults: priorDefaults)
        priorStore.migrateLegacyConnectionsIfNeeded(hasPriorUsage: true)
        guard priorStore.hasCompletedEnrollment,
              priorStore.isEnabled(.codex),
              priorStore.isEnabled(.cursor) else {
            failures.append("Prior usage without connection keys should default-enable returning providers")
            return
        }
    }

    private static func checkCatalogDescriptors(_ failures: inout [String]) {
        let providers = ProviderCatalog.enrollableProviders
        guard providers == UsageProviderIdentity.allCases else {
            failures.append("Catalog must expose every enrollable identity")
            return
        }
        for provider in providers {
            let descriptor = ProviderCatalog.descriptor(for: provider)
            guard descriptor.identity == provider,
                  descriptor.supportState == provider.supportState,
                  !descriptor.summary.isEmpty else {
                failures.append("Descriptor missing for \(provider.name)")
                return
            }
        }
    }

    private static func checkPrivacyLivesOnIdentity(_ failures: inout [String]) {
        for provider in UsageProviderIdentity.allCases {
            guard provider.collectionDisclosure.contains("never")
                    || provider.collectionDisclosure.contains("stay out") else {
                failures.append("\(provider.name) detail disclosure must state privacy boundary")
                return
            }
        }
    }
}
