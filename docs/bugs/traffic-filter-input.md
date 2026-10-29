# Traffic filter input regression prevention

## Evidence and reproduction
The fixed browser source has six separate timeout effects and compares applied text, not merely lowered numeric values. The initial RED checkpoint5e5b39d intentionally fails to compile because the reducer types are absent; it is not a reproduced runtime defect. Implementation17d094b passes14 cases. Expanded checkpointb0a593c passes17, including real TrafficStore.configure acceptance/rejection without transport. No production bug is asserted from that compile failure.

## Analysis
Five Whys (preventive): a history page could reset unexpectedly if pending and applied text were conflated; that conflation could flush all fields on an immediate control; one shared debounce generation would also discard independent field edits; String equality would hide byte-distinct NFC/NFD; counting only numeric equality would hide an applied 1→01 change. Preserve the browser's separate raw/applied identities and per-field revisions instead. These are hypothesized regression paths tested before screen integration, not claims of failures observed in an installed app.

Fishbone: timing—independent tickets versus timer execution; identity—UTF8 versus canonical equality; query—text identity versus optional numeric predicates; ownership—presentation and transactional adoption; acceptance—pure reducer/store configuration versus actual VM/UI.

Timeline: source contract and bilingual design → missing-type RED5e5b39d →14GREEN17d094b →17-case store integrationb0a593c → full tests/coverage and read-only review. The code's copied proposals permit a rejected configuration to leave the applied state untouched. Advanced reset invalidates retired advanced tickets while retaining the host timer.

## Recurrence and limits
Keep stale/retyped/replaced tickets, Unicode trim, ignored/overflow/inverted bounds, normalized no-ops and rejected store configurations. The screen model must merge each field into the current applied query, validate current presentation and modal ownership, adopt proposals synchronously only after acceptance and retain sibling timers across store-owner rotation. This file does not prove actual300ms timing, timer cancellation, UI rendering, read polling, real-server deletion, browser equivalence or whole-product completion.
