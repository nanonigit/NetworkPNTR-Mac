# 番号付きツール実行とLinuxプロセス再起動の検証

cloud2は固定norma v0.4.3に履歴パッチと番号付き実行パッチを順に適用する。実ChatAgentのストリーミング経路で、引数より先に署名が来る場合や、複数呼び出しの引数が交互に届く場合を修正した。完了した番号付き応答を待ち、生引数とIDを確認して、履歴と同じブロックを実行する。開始前の断片は対応する開始へ結合。未対応・壊れた引数、重複や欠落したID、未完了応答は番号付きツールの投入前に拒否する。キュー、セマフォ待ち、実行は元ターンの文脈で扱う。通常の番号なしツールの実行経路も維持する。詳細はcloud-indexed-execution-designとbugs/cloud-indexed-executionを参照。

実HTTPプロバイダーとChatAgentを使い、ストリーム有無の両方で別プロセス復元に成功した。同じ履歴ファイルを使う2つのLinux子プロセスを起動した。初回は固定Readを1回実行し、署名付き履歴と結果を送る。初回終了後に親が証拠ファイルを削除した。次のプロセスでは履歴を読み、同じID・署名・引数・保存済み結果を再送し、新規ツール実行0件のまま応答を追記した。ループバックの模擬サービスが受けた要求は各方式3件。子プロセスでも接続先とパスを検証した。結果は実Readの出力を照合した。

外部通信なしの全Go関連試験は589成功・既存116スキップのイベント。親と副試験を含む。内訳はllm77、harness58、traffic62、agent78、server314の成功。agent14、server102のスキップは未検証。Python成果物試験179件成功。SDK両パッケージを計測し、harnessからのllm呼び出しも含めた。文カバレッジはstreamAndExecute88.5%、ToolInputsAreValid88.9%、queue／processQueue100%。既存範囲を含むexecOne65.8%、SDK2パッケージ全体78.3%。

Linux/arm64のCGO無効本体はartex-mac-e75ae371-cloud2。ELFは29360290バイト、SHA-2560455fb4255796a6c1ba1dc5545cbdbb39f722492ca6e48775f8ce8ff7b16e6bf。ビルダーイメージはsha256:998d694fa51fa016012653f7cf545befc7dbe867267ae2c0f89d806364492589。適用したパッチと依存ソースの変更ファイルがイメージ内と完全一致することを確認した。Goビルド情報で管理依存の置換とプラットフォームを照合した。本体は無視対象 `.build-cache/managed-backend-cloud-v2/artex` に保持する。

再現にはcloud-tool-history-verification記載の固定アーカイブとtraffic／agent／serverオーバーレイを使う。コミット `037a310` のDockerfile.provider-testsを使い、ビルドコンテキスト直下に `norma-indexed-tool-execution.patch`、`norma-tool-history.patch`、`managed.patch` を置く。agentオーバーレイは `cloud_chat_transcript_test.go` を含む。固定依存を検証し、両パッチを検査してから適用する。SDK試験は実アプリの依存グラフで動かす。対象試験は外部通信なしのビルダー内で `go test -p 2 -mod=readonly ./agent -run '^TestManagedCloudCompatibilityChatTranscript(Endpoint)?$' -count=1`。固定ブラウザはe75ae371。

実行範囲は、実ChatAgent・ツール実行・履歴ファイルを使うLinuxのプロセス再起動。次の条件は通常チャットAPIと状態ディスクを通す専用VM再起動。実クラウド、Mac画面とブラウザの比較、既定ゲスト昇格、リリース検証も残る。ホストCIの利用可否は未検証で、公開は `[skip ci]` を使用する。
