# Track runtime sources with provider provenance

Pi is a runtime that can route activity to multiple underlying model providers. Track Pi as its own selected provider connection and retain the underlying provider/model reported by its local session metadata.

Do not automatically add Pi consumption to an underlying-provider card or to a combined total that also includes that provider. Cross-source duplicate identity is not established, and silently merging totals risks counting the same activity twice. Pi therefore has its own card and token totals; incomplete or unknown model pricing leaves its cost subtotal explicitly incomplete.

Provider enrollment is separate from source capability. First-launch onboarding lets the user select providers using support-state indicators only. Provider collection and privacy disclosure appear only when the user opens that provider's detail settings screen. A user can skip onboarding and enable, pause, or remove connections later.
