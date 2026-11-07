# Guest output language

The Mac language selector supports English and Japanese. Apply the selection
to the authenticated dedicated guest's output-language setting, including
after login and restart. Leave the pinned browser and stored prompt content
as they are.

Read the current language from the pinned settings endpoint. If it differs,
send only the selected output language and verify the response. A serial
worker coalesces pending selections and checks the current authentication
epoch before writing. It does not replay an ambiguous write automatically.
A further selection or authentication epoch can reconcile the setting.
Failures are logged without response contents or credentials.

Exercise both wire values, unknown legacy settings, matching no-op, changes
during a held request, logout, and rejected replies. Compare the contract
with the frozen browser backend and verify persistence in the dedicated VM.

The disposable pinned browser API accepted `ko`, `en` and `ja` in
sequence and preserved traffic capture, LLM recording and web-search
settings. A signed probe linked the production Mac synchronizer to the
current guest. It started with a persisted `ko`, wrote `en` and `ja`
through the synchronizer, and read each value back after a separate VM
restart. All three boots stopped cooperatively with zero NICs and shares.
The language picker and live generation still require interactive checks.
[Verification receipt](../evidence/llm/guest-output-language.json)
