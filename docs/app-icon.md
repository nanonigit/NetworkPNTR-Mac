# NetworkPNTR Mac app icon

## Requirements / 要件

Use the supplied ethical-hacking silhouette as a visual reference. The icon must remain recognizable at Dock/Finder sizes, preserve the NetworkPNTR Mac name, and be included in every subsequent bundle build. Do not change VM artifacts, application data, authentication or runtime behavior.

提供された図柄を参考に、ネットワークと防御を示すアプリアイコンを制作する。Dock・Finderの小さい表示でも識別でき、以後のビルドにも含める。名称、VM、保存データ、認証、実行動作は変更しない。

## Design / 設計

A silver ethical hacker and laptop, shield/check and teal network nodes on a midnight navy rounded-square tile. Transparent exterior, no lettering. The user reference is not redistributed. The final generated master lives in `assets/branding/networkpntr-app-icon.png`. Produce standard 16–1024px macOS icon representations using system `sips` and `iconutil`; copy `AppIcon.icns` into bundle Resources and set `CFBundleIconFile` before signing. Both existing default and Cloud Preview bundles receive only the icon/plist/signature change. No UI layout is changed; Lazyweb screen research is out of scope for this graphic and packaging task.

紺色の角丸タイルに銀色の人物・ノートPC、盾とチェック、青緑のネットワークを組み合わせる。文字は入れず、外側は透明とする。原画からmacOS標準の各サイズを生成し、署名前にバンドルへ組み込む。通常版・Cloud Preview版の既存バイナリとゲストは維持する。画面レイアウト変更ではないためLazywebのUI調査は対象外。

## Implementation and verification / 実装・検証

- [x] Generate and inspect the referenced design; save master in the repository.
- [x] Add reproducible icon packaging and bundle metadata.
- [x] Decode the ICNS and verify its representations and alpha channel.
- [x] Update both local bundles, verify signatures, and compare guest/helper hashes before and after. The main executable is re-signed and therefore its whole-file hash changes.
- [x] Verify macOS resolves the bundle icon through NSWorkspace.

Built-in imagegen was used. Prompt summary: reinterpret the supplied ethical-hacking silhouette as a professional macOS icon; silver/white central motif, teal network accents, dark navy rounded tile, transparent exterior, no text, clear small-size silhouette. No CLI/API fallback was used.

Verification receipt: [app icon](../evidence/branding/networkpntr-app-icon.json). Both system-resolved icons were visually inspected at 128px; the ICNS was also inspected at 32px. The installed local bundles were updated in place without rebuilding pending VM changes.

Apple reference: [CFBundleIconFile](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleiconfile).
