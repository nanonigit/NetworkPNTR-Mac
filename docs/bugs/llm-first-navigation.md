# LLM settings stay on the loading view at first navigation

A signed Mac app with a disposable authenticated Linux VM showed a
spinner on the first visit to LLM settings. Visiting Account and
returning to LLM showed the empty profile screen. The Gemini choice
then opened the editor with the expected endpoint and a blank key.

The loading branch calls the workspace's ownership predicate. On first
entry, owner comparison fails before reading the observable store.
SwiftUI therefore misses the store assignment made by the loading
task. Read the observable store before testing the private owner so
the first attachment invalidates the view. Preserve the existing
same-owner, owner-change and sign-out rules.

The regression subscribes to the same predicate from an empty
workspace and requires a change notification on first attachment.
The real acceptance check opens LLM once in a fresh signed app and
waits for the New menu to appear without navigating away.

The focused test reproduced the missing notification before the fix and
passed afterward. The signed app then showed New on first navigation in
both Japanese and English. The UI test opened all five choices in
Japanese and checked their initial format and endpoint, blank secure
key field and disabled Save. Down and Return selected the first option,
and Escape closed its editor.

The same review found that the editor and rotation sheets ignored
the application's English selection. Both presentations now pass the
parent's locale to the sheet content. A new signed run showed the Groq
editor and rotation sheet in English and the custom editor in Japanese
after switching back. The empty profile list remained empty. The live
frozen browser returned to its login screen, so the current comparison
used its pinned source and the previously recorded control inventory
and image. Current authenticated browser interaction and VoiceOver
remain open.
