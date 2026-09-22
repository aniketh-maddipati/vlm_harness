# Model assist — threat model

**Scope:** `Lumina/Services/ModelClient.swift`, `AskCommand.swift`, `AskScopeResolver.swift`,
`AskPlanApply.swift`, `Lumina/Develop/ModelAutoDevelop.swift`,
`Lumina/ViewModels/P0SessionModel+Model.swift`.
**Authority:** `design/contract-v6.md` D67 / R-N.1 (loopback-only), D45 (no automatic egress),
D4 / D36 (sovereignty). Every mitigation below is pinned by a named test; a mitigation
without a test is listed as residual risk, not as a defense.

## What is being protected

| Asset | Why it matters |
|---|---|
| The photographs (RAW and previews) | The whole reason D4 exists. Nothing leaves the machine. |
| The photographer's decisions: cull, hand recipes, final order | The model must never make or unmake one. |
| Provenance (`RecipeSource`) | A model result must never pass as a hand edit, or vice versa. |
| Undo integrity | One ⌘Z must return to what the photographer last saw. |
| The audit's claims | "No off-device network calls" must stay literally true. |

## Trust boundaries

```
 keyboard ──request text──▶ ┌───────────────┐
 memory card ──filename───▶ │  Ask planner  │──JSON (closed vocabulary)──▶ parse: drop unknown
                            └───────┬───────┘
                                    │ loopback only (127.0.0.1 / ::1)
                            ┌───────▼───────┐
 preview JPEG ≤512 px ────▶ │ local model   │  ◀── operator-run; NOT trusted
                            └───────┬───────┘
                                    │ JSON (schema) ──▶ bound / band / echo guard
                            ┌───────▼───────┐
                            │ session       │  snapshot-checked, one batch, no cull
                            └───────────────┘
```

**The model server is not trusted.** It is on loopback, but anything can listen on a
port. Every defense below holds against a *malicious* server, not just a wrong one.

## Threats and mitigations

| # | Threat | Mitigation | Pinned by |
|---|---|---|---|
| T1 | Off-device egress — pixels or text reach a hosted endpoint | `ModelEndpoint.init` is failable and refuses any non-loopback host; `loopbackEndpoint` refuses a non-loopback env override and keeps the compiled-in default; `banned_patterns` fails any non-loopback `URL(string:)` literal in the strict tree and permits `URLSession.shared` in one file | `ModelClientTests.testEndpointRefusesAnythingThatIsNotLoopback`, `…testNonLoopbackOverrideIsRefusedAndTheDefaultStands`, `…testShippedEndpointsAreLoopback`; lint `banned_patterns` |
| T2 | Credential exposure — a key in source, log, or header | There is no key. `apiKey` was removed from the type; no Keychain read; no `Authorization` header can be constructed | `ModelClientTests.testNoAuthorizationHeaderIsEverSent` |
| T3 | Request leakage into logs via error text | `ChatCompletionsClient.errorMessage` returns only the server's message or a 200-byte prefix of the body — never the request | `ModelClientTests.testHTTPErrorCarriesTheServerMessageNeverTheRequest` |
| T4 | Prompt injection via filename or request text talks the model into culling / large edits / other frames | The model answers only in a closed vocabulary (six scopes, four actions). Unknown scope or action is **dropped, not guessed**. The model never sees or names asset IDs — scopes are relationships the app resolves. Filename and request are stripped of control characters and line breaks and length-capped before they enter the prompt | `ModelEdgeTests.testInjectedInstructionsCanOnlyEverYieldVocabularySteps`, `…testFilenameAndRequestCannotOpenANewLineInThePrompt`, `AskPlannerTests.testUnknownActionDropsTheStep`, `…testKeywordsNeverProduceACullingStep` |
| T5 | Malicious / broken server returns extreme or nonsensical values | Every adjust delta is clamped to `AskDelta.Bound`; every auto move is clamped into `ModelAutoDevelop.Band`; WB is a bounded *shift*; inert controls pinned to 0; slider range enforced at apply; geometry never touched by sync | `AskPlannerTests.testDeltaIsClampedToTheAskBound`, `ModelAutoDevelopTests.testEveryToneMoveIsClampedIntoItsBand`, `…testWhiteBalanceIsAShiftFromTheBaseNotAnAbsolute`, `AskApplyTests.testSyncCopiesOnlyTheNamedGroupsAndNeverGeometry` |
| T6 | Server echoes prompt statistics back as edits | `ModelAutoDevelop.isEcho` refuses any proposal reproducing a quoted non-zero statistic at prompt precision; deterministic recipe stands | `ModelAutoDevelopTests.testEchoedStatisticIsRefused`, `…testQuotedStatisticsMatchWhatThePromptActuallyPrints` |
| T7 | Resource exhaustion — oversized or deeply nested reply, slow server, unbounded fan-out | Reply refused above `maxResponseBytes` (256 KB) before parsing; per-request timeout on the endpoint; at most 4 frames in flight; batch is all-or-nothing so a slow frame delays but never tears | `ModelEdgeTests.testOversizedReplyIsRefusedBeforeParsing`, `…testDeeplyNestedReplyDoesNotCrash`, `ModelRaceTests.testAtMostFourFramesAreInFlightAndTheBatchIsOneUndoStep` |
| T8 | Stale write — a model answer lands over a hand edit, an undo, or a removed frame | Every frame is snapshotted at dispatch (recipe fingerprint + provenance). A result becomes a mark only if the frame still exists and neither has moved | `ModelRaceTests.testHandEditWhileTheModelThinksWinsForThatFrameOnly`, `…testUndoDuringFlightMakesTheInFlightAnswerStale`, `…testFrameRemovedDuringFlightProducesNoMark`, `…testTwoBatchesOnTheSameFramesAreTwoUndoStepsWithNoTornState` |
| T9 | Torn batch — cancellation or partial failure leaves half a pass applied | Nothing commits until every frame has answered or fallen back; a batch cancelled before it starts fans nothing out, and one cancelled in flight commits nothing; a per-frame failure falls back to the deterministic recipe inside the same batch | `ModelRaceTests.testCancelledBeforeStartSendsNothingAndCommitsNothing`, `…testCancellationWhileInFlightCommitsNothing`, `…testNothingCommitsUntilEveryFrameHasAnswered`, `…testOneUnreachableFrameFallsBackWhileTheRestTakeTheModel` |
| T10 | Plan drift — a plan previewed as "12 frames" applies to 40 after focus moves | `AskPlan.expectedCounts` records what each scope resolved to at planning; `applyPlan` refuses the whole plan if any used scope now resolves differently | `ModelRaceTests.testPlanAppliesToWhatWasPreviewedOrNotAtAll` |
| T11 | Cull / final order / selection touched by the model | No code path in `AskPlanApply` or `ModelAutoBatch` reads or writes `cull`; `commitBatchEdit` restores selection and final order around the mutation | `AskApplyTests.testCullSelectionAndOrderAreNeverTouched` |
| T12 | Provenance laundering — a model result recorded as `.hand`, or a hand edit as `.auto` | `RecipeSource.model` is distinct; `AskPlanApply.handSource` maps engine bases to `.autoHand`; marks carry `sourceBefore`/`sourceAfter` so undo restores provenance, not just values | `AskApplyTests.testAdjustOnShotBecomesHandOnEngineBecomesAutoHand`, `…testMultiStepPlanIsOneUndoAndRestoresRecipesAndSources` |
| T13 | Silent overwrite of hand or sidecar recipes by auto | Same skip rule as `applyAuto`: non-`.shot` frames skipped unless `force`, and skipped frames are never sent | `ModelEdgeTests.testModelAutoSkipsHandAndSidecarFramesUnlessForced` |
| T14 | Invented corrections on unmeasured frames | No `ImageStats` → no dispatch, no request, no mark | `ModelEdgeTests.testModelAutoWithNoMeasurementsSendsNothing`, `ModelAutoDevelopTests.testNoPreviewMeansNoNetworkCallAtAll` |

## Residual risks (known, accepted, or deferred)

- **Band-edge values pass.** `exposure −1` on a dark frame sits exactly at
  `Band.exposure.lowerBound` and passes both the echo guard and the band. Pinned by
  `ModelAutoDevelopTests.testBandEdgeValuePassesBothGuardAndBand` so a tightening is a
  deliberate change. Candidate fix: make the band asymmetric around the deterministic
  value rather than around zero.
- **The catalog is trusted.** `ModelImage.jpeg(forPreviewAt:)` reads whatever path the
  `AssetRecord` names. A tampered catalog could point it at an arbitrary readable file;
  the file is only ever *read* and *downscaled*, never written or executed, and it goes
  only to loopback. Not mitigated here because the catalog is already the trust root for
  every other read in the app.
- **A malicious loopback listener can see the preview.** D67 accepts this by
  construction: the operator runs the server. A ≤512 px JPEG of the frame is the
  maximum exposure. Mitigating it would mean authenticating the local server, which the
  ruling did not ask for.
- **Timeout granularity.** A slow frame holds the batch for up to `endpoint.timeout`
  (60 s for vision). Acceptable for a first pass; a per-batch deadline is a follow-up if
  the latency fixtures say so.
- **Sanitization is a hygiene measure, not the defense.** `promptSafe` keeps the prompt
  well-formed; the actual defense against injection is the closed vocabulary and
  drop-not-guess parsing. If the vocabulary ever grows a free-text or ID-bearing field,
  T4 must be re-evaluated.
- **No rate limit on `planAsk`.** A held ⏎ could issue many requests to the local
  server. It is the operator's own machine and server; the cost is theirs alone. Revisit
  if a UI ever auto-issues asks.

## Out of scope

- Hosted providers of any kind (deleted under D67, not disabled).
- The deterministic `AutoDevelop` pass (no model, no network, covered by its own tests).
- UI surfaces (⌘K field, key routing, Esc order, labels) — they rejoin on the UI branch and
  inherit these guarantees from the session layer.
