# Apple Foundation Models

Settings, then Apple Intelligence, picks the Emblem server, Apple's on-device model or Apple's Private Cloud Compute (PCC) model. The choice persists across launches. A failed Apple-model request shows its error and is never retried on the server.

## On device

Turn on Apple Intelligence on an eligible device and let its model finish downloading. Apple-model pages need iOS 26.4 or later, because Emblem uses the framework's tokenizer and context size to budget the prompt, schema, tools and output. The app itself runs on iOS 26.

The adapter generates typed `@Generable` values (facts, steps, cards, charts, comparisons, writing drafts and more) and turns partial snapshots into normal Emblem blocks. Only a valid final response completes the run.

Public web search is a separate setting, "Allow public web search". When it is on, the model's search queries go to Emblem's `/api/tools` relay. It never reads Gmail or calendar data. With it off, Apple-model generation does not use the server.

On iOS 27, image attachments are sent only when the selected model supports vision. Requests that need server-only connected data or actions fail with an explanation. Context from server pages is never passed to Apple models.

The client records each page's origin when it sends the request. Speech for an Apple-model page uses the system synthesizer, never the server voice route. Apple-model writing drafts can be edited locally but not sent for server tone rewrites.

## Private Cloud Compute

This path uses `PrivateCloudComputeLanguageModel`. It needs iOS 27, an eligible device, internet access and Apple's managed entitlement. The framework reports the daily limit. The default build has no PCC entitlement, and Emblem reports PCC as unavailable.

Getting the entitlement is up to Apple; see [Apple's access requirements](https://developer.apple.com/private-cloud-compute/). Once your signing profile includes it, set this in `ios/Local.xcconfig`, regenerate the project and rebuild:

```xcconfig
EMBLEM_CODE_SIGN_ENTITLEMENTS = Entitlements/PrivateCloudCompute.entitlements
```

That file grants only `com.apple.developer.private-cloud-compute`. An app that needs other capabilities must add them.

The iOS 27 SDK has no public PCC tokenizer. Emblem estimates the input from its UTF-8 size plus schema, tool, image and reasoning allowances, and the framework enforces the final limit.

API references: [guided generation](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models), [tools](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling), [PCC](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute).
