import Foundation

enum ProviderCardPresentationFactory {
    static func codex(
        projection: CodexUsageProjection,
        quota: CodexQuotaPublication,
        retainedQuota: CodexQuotaSnapshot?,
        models: [UsageModelTotal],
        trend: [UsageTrendBucket]
    ) -> ProviderCardPresentation {
        let quotaContent = codexQuota(quota, retained: retainedQuota)
        return ProviderCardPresentation(
            provider: .codex,
            plan: "Plus",
            trailingLabel: "Local device activity",
            contentSpacing: 14,
            messagesBeforeQuota: codexQuotaMessages(quota, retained: retainedQuota),
            quota: quotaContent,
            details: ProviderCardDetails(
                rows: [
                    ProviderMetricRow(name: "Input", tokens: projection.inputTokens),
                    ProviderMetricRow(name: "Cached input", tokens: projection.cachedInputTokens),
                    ProviderMetricRow(name: "Output", tokens: projection.outputTokens)
                ],
                totalTokens: projection.totalTokens,
                showsDividerBeforeTotal: true,
                models: models,
                trend: trend,
                status: codexStatus(projection)
            )
        )
    }

    static func cursor(
        projection: CursorUsageProjection,
        quota: CursorQuotaPublication,
        connectionMessage: String?,
        isConnecting: Bool,
        models: [UsageModelTotal],
        trend: [UsageTrendBucket],
        lastSuccessfulRefreshAt: Date?
    ) -> ProviderCardPresentation {
        var messages: [ProviderCardMessage] = []
        if projection.workspaceName == nil {
            messages.append(
                ProviderCardMessage(
                    text: isConnecting ? "Opening Cursor sign-in in your browser…" : "Cursor sign-in starts automatically when this panel opens.",
                    style: .secondary
                )
            )
        }
        if let connectionMessage {
            messages.append(ProviderCardMessage(text: connectionMessage, style: .secondary))
        }

        return ProviderCardPresentation(
            provider: .cursor,
            plan: "Premium",
            trailingLabel: projection.workspaceName,
            contentSpacing: 10,
            messagesBeforeQuota: messages,
            quota: cursorQuota(quota),
            details: ProviderCardDetails(
                rows: [
                    ProviderMetricRow(name: "Input", tokens: projection.inputTokens),
                    ProviderMetricRow(name: "Cache read", tokens: projection.cacheReadTokens),
                    ProviderMetricRow(name: "Cache write", tokens: projection.cacheWriteTokens),
                    ProviderMetricRow(name: "Output", tokens: projection.outputTokens)
                ],
                totalTokens: projection.totalTokens,
                showsDividerBeforeTotal: false,
                models: models,
                trend: trend,
                status: cursorStatus(projection, lastSuccessfulRefreshAt: lastSuccessfulRefreshAt)
            )
        )
    }

    private static func codexQuotaMessages(_ publication: CodexQuotaPublication, retained: CodexQuotaSnapshot?) -> [ProviderCardMessage] {
        switch publication {
        case .awaitingIdentityConfirmation(_, let pending):
            let retainedLabel = retained.map { "Keeping quota for \($0.accountIdentity)." }
                ?? "Quota publication is paused."
            return [ProviderCardMessage(text: "Confirm new Codex account \(pending) in Settings. \(retainedLabel)", style: .warning)]
        default:
            return []
        }
    }

    private static func codexQuota(_ publication: CodexQuotaPublication, retained: CodexQuotaSnapshot?) -> ProviderQuotaContent {
        switch publication {
        case .published(let snapshot):
            .windows(snapshot.windows.map(quotaWindow))
        case .authenticationMissing:
            .message(ProviderCardMessage(text: "Codex quota unavailable until Codex authentication can be read.", style: .secondary))
        case .authenticationExpired:
            .message(ProviderCardMessage(text: "Renew authentication in Codex, then refresh.", style: .warning))
        case .awaitingIdentityConfirmation:
            if let retained {
                .windows(retained.windows.map(quotaWindow))
            } else {
                .message(ProviderCardMessage(text: "Quota publication paused until the new Codex account is confirmed.", style: .warning))
            }
        case .unavailable(let message, let retainedSnapshot):
            if let retainedSnapshot {
                .windows(retainedSnapshot.windows.map(quotaWindow))
            } else {
                .message(ProviderCardMessage(text: message, style: .error))
            }
        }
    }

    private static func cursorQuota(_ publication: CursorQuotaPublication) -> ProviderQuotaContent {
        switch publication {
        case .published(let windows):
            .windows(windows.map(quotaWindow))
        case .unavailable(let message):
            .message(ProviderCardMessage(text: message, style: .secondary))
        }
    }

    private static func quotaWindow(_ window: CodexQuotaWindow) -> ProviderQuotaWindowPresentation {
        ProviderQuotaWindowPresentation(id: window.id, name: window.name, remainingFraction: window.remainingFraction, resetsAt: window.resetsAt)
    }

    private static func quotaWindow(_ window: CursorQuotaWindow) -> ProviderQuotaWindowPresentation {
        ProviderQuotaWindowPresentation(id: window.id, name: window.name, remainingFraction: window.remainingFraction, resetsAt: window.resetsAt)
    }

    private static func codexStatus(_ projection: CodexUsageProjection) -> ProviderCardMessage {
        switch projection.coverage {
        case .accessError(let message):
            ProviderCardMessage(text: message, style: .error)
        case .importing:
            ProviderCardMessage(text: "Importing available local sessions…", style: .progress)
        case .empty:
            ProviderCardMessage(text: "No token records were found. This does not establish complete history.", style: .secondary)
        case .available:
            ProviderCardMessage(
                text: "Observation cutoff: \(projection.cutoff?.formatted(date: .omitted, time: .shortened) ?? "unknown") · \(projection.records) normalized records",
                style: .secondary
            )
        }
    }

    private static func cursorStatus(_ projection: CursorUsageProjection, lastSuccessfulRefreshAt: Date? = nil) -> ProviderCardMessage {
        switch projection.coverage {
        case .unavailable(let message):
            let suffix = lastSuccessfulRefreshAt.map { " Showing data from \($0.formatted(date: .abbreviated, time: .shortened))." } ?? ""
            return ProviderCardMessage(text: message + suffix, style: .error)
        default:
            return ProviderCardMessage(text: projection.coverage.label, style: .secondary)
        }
    }
}
