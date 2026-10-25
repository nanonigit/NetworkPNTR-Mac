# T7 実添付の検証

新規の実VMで本番添付クライアントを試験し、独立した固定参照版と比較しました。4ファイルを2回送り保存された8バージョンの名前/相対パス/サイズ/SHA256と、正規化した日英の説明一覧が完全一致。実ダウンロード12回で全内容を照合し、再送後の初回4ファイルも保持されていました。有限の添付通信/読戻し契約の成功で、タスク作成UI全体や再起動後の永続化の合格ではありません。

署名VMProbe --task-stagingはB1の別保存候補、新規2GiB状態、起動1回、メモリのみの認証Vaultと使い捨て口座/パスワードを使用。タスク/会話/エージェント/クラウド要求、NIC/ホスト共有/汎用RPC、Mac Keychain/既存ユーザーデータは使いません。14.85秒・終了0、準備/未初期化認証/保護401/正常停止に成功。停止後の上限付き全シリアルログで既知異常と試験秘密値なし、隔離4証跡ゼロ、VM解放を確認。過去panicは未解決で単発成功から信頼性は認定しません。実行PATHは/usr/bin:/bin、DOCKER_HOSTは使用不能ですがDocker Desktopは比較/ブラウザ用に稼働中のため、Docker停止/新規Mac合格とは区別します。

参照試行を保持。Aは読み取り専用rootへのdocker cpが拒否（/tmpがtmpfsでも同じ）され、アプリ/ネットなしの独立コピー反例で終了1を再現。Bはスクリプト転送後、本体がJWT保存前提で停止：/opt/artex/jwt.keyのリンク先/state/jwt.keyに対し/state/dataだけを書込み可能にしていました。Cはroot読取専用を維持、固定3スクリプトをuid1000の/tmpへ転送し、JWTと/dataを含む/stateを使い捨てtmpfsにして同じ本体/引数をexec。Cは終了0・完全一致。A/Bを添付成功とはせず、実VMを再起動していません。全参照コンテナ/ネットワークの消滅を確認し、私有envファイルを削除、既存ブラウザ4コンテナのIDも不変です。

両本体は固定e75ae371ad777ffd1eecdd28d2781a6519b05591由来、SHA2560ebad83ddda276b03b415d64ce30af44e7a587860f3b660c12563462a0ac5e80で一致。参照PostgreSQLも固定ID、root読取専用、UID999/1000、cap-dropALL/no-new-privileges、内部ネットワーク、公開ポート/ホストbind/socketなし・使い捨てtmpfsのみ。VMのkernel/initramfs/systemハッシュは不変を再検証し、通常ゲストへ未昇格。環境ごとのdataルート差は既知の合成下書きパスだけ正規化。MacのファイルURLが返すe+U0301の分解Unicodeを保持し、製品で名前を変換しません。参照版の一覧は固定appendUploadsをNodeで評価。T6の純粋関数126ケースは別の補助証拠です。

TDD：30339f0未実装compileRED、1fd297bは試験名の実行RED3失敗/4件→7a9b58e GREEN4（製品の名前正規化変更ではなく試験データの表記）。8935fad有限CLI追加。ab1c1be Python未実装RED→56ba489 GREEN2、f2adde4終了レポート未実装RED/Python環境ガード3成功→0504549 GREEN5、26cd220後片付け未実装RED→10b82f5 GREEN3。実機前にレビュー指摘を修正。転送/起動完了後の終了失敗でも合格にせず、ログ/削除のタイムアウトで残資源の削除試行を飛ばさない模擬試験を保持。ホスト/指定なしLinux/root UIDはHTTP前に拒否。[調査](bugs/task-staging-runtime-investigation.md)参照。

最終回帰はCore295+Mac68=Swift363件、成功362・既存AX1スキップ、終了0。Python60成功・終了0。Core試験処理の行100%/領域97.06%、終了レポート100%。既存出力拒否試験は起動前に終了1でマーカー/フォルダを保持し状態を生成しません。アプリbuild-only終了0・strictアドホック署名成功、起動/インストールはしていません。UIリソース/目録21機能・27画面・243ハンドラは保持。UI変更なしでLazyweb対象外です。

公開証拠は合成データ/正規化結果だけ：[VM](../evidence/tasks/t7-vm-result.json)、[参照](../evidence/tasks/t7-reference-result.json)、[比較](../evidence/tasks/t7-comparison.json)、[検証](../evidence/tasks/t7-verification.json)。生ログ/状態ディスク/秘密/env/バイナリはGit対象外。失敗を消さずレシピハッシュと安全な状態を追跡します。

実選択/OS権限/画面操作、添付本文を使う作成/保存、大容量/部分失敗の操作、再起動後の保存/復旧/信頼性、残タスク/全21機能、ネイティブ外部通信、製品配布/新規Mac導入は未完了です。Mac解除は利用者希望で後日としてCUAを再試行していません。全体目標を継続します。
