# Apple Virtualization でのクラウド中継検証

署名済み DEBUG プローブで Linux ARM64 の cloud5 候補を、新規の
2 GiB データディスクで起動した。稼働中のバックエンドのバージョンと、
未認証時の 401 応答を確認してから、通常の認証済み LLM・チャット API を使った。
OpenAI、Anthropic、Gemini、Groq の各設定で模擬モデルが1件ずつ返り、期待した最終応答が
チャット履歴に保存された。ホストは4件のモデル一覧と4件のチャットを順に受けた。
5件目のチャットは SSE の途中で保留し、VM の正常停止で通信がキャンセルされ、
VM が解放された。監査で初回フォーマット、ループバックのみ、共有マウントなし、
ログへの資格情報の出力なしを確認した。

4社を対象にした初回試験は、模擬 API が Anthropic の経路を受け付けず、
モデル一覧で停止した。経路の追加後は、最終ユーザーメッセージの先頭ブロックに
プロンプトがないためチャットで停止した。再試験ではテキストブロック内の
完全一致でプロンプトを確認し、API キーとバージョンのヘッダーを照合した上で、
Messages 形式のイベントを通常の HTTP フレーマー経由で返した。
[Anthropic のストリーミング仕様](https://platform.claude.com/docs/en/build-with-claude/streaming)

固定したクラウドプロファイルのイメージと cloud5 バックエンドを、既存のゲスト用
Dockerfile でビルドした。ビルド時のネットワークは無効にした。継承した init の
変更はバックエンド起動時に `ARTEX_MAC_CLOUD_EGRESS=vsock-v1` を設定する箇所だけ。
実行時は保存済みのカーネルと initramfs を用いて Apple Virtualization で起動した。
マニフェストはカーネル、initramfs、システムディスクを固定する。
[検証記録](../evidence/llm/cloud-egress-vm-verification.json)

再実行時は `swift build --product VMProbe` で作ったバイナリをコピーし、
`guest/entitlements.plist` を指定して署名する。検証済み候補に対して
`VMProbe --cloud-vsock ARTIFACTS NEW_PRIVATE_OUTPUT` を実行する。
マニフェストの改変や既存出力先は起動前に拒否され、Release ではこのフラグを
利用できない。今回の外部 API 応答は模擬データで、ゲストと Mac の virtio 通信は
実機で検証した。実 API、通常起動での有効化、
ブラウザ版との比較は今後の検証項目。
