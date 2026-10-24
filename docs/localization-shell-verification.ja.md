# ネイティブ言語切り替え (L2)

要件→設計→タスク後、2de5dfaで未実装RED、f779ceaでカタログ4テストGREEN。5a66610はAppの単一State設定をRootのPickerへ渡し、言語.idを使わず表示を変更。ブラウザの実名称6か所はd949dc8 RED6→ad9a7fe GREEN5試験で修正した。

署名5a66610のVM V1で候補はEnglish/日本語のみ。ja→en→jaでも同じChat／会話表示、本文L2 draft **literal**＋改行日本語 中文 한국어、locale-l2.txt23Bカードを保持。ready表示も保持したがVZオブジェクト同一性を別計測はしていない。別プロセスV2でも選択済みenを保持し、元のjaへ復帰。両終了0、VM停止・Keychain削除。参照ブラウザはen→ja→enで5候補、nativeは意図した2候補。21機能IDの共通名称は翻訳したが各機能の実装合格とは無関係。

全Swift234件（成功233・既知AX1スキップ）、Python49成功。Coreヘルパー行100%・領域97.4%。新規scratchで初期3ケース、最終5ケースと全体試験も成功。最終署名ad9a7fe同梱はen/jaだけで修正済み6名称も検証。画像は名称修正前5a66610であり、英語表示と状態保持コードは変更していない。最終日本語画像を再確認したとは主張しない。

初回incremental試験はキーを返し93assertions失敗。トップのコンパイル済みbundleには両リソースがあった。機能コードを変えない一時パスprobeでネストされた試験bundleを確認後に成功し、新規scratchも成功。最初の原因は未確定で、Foundation／製品不具合と断定しない。warm cache成功を信頼性全体の証明にせず、cold CI・署名リソース・実画面を分けて扱う。

MUSUBI: 未実装と名称不一致を再現、カタログ・cold build・AX画像収集、分析、修正、検証。名称の5 Whysは独立翻訳→意味が近ければ十分と仮定→固定名称を未照合→参照の実名称を試験で固定する必要。Fishboneはリソース同梱・locale所有権・view同一性・内容出典・用語・cold/incremental。Timelineは調査→仕様→RED/GREEN→cold probe→接続/レビュー→実切替→用語RED/GREEN→最終試験/同梱検証。再発防止は型付きキー・21対応・英語フォールバック・変数保持・名称固定・言語.id禁止・外部入力／添付比較。

Lazyweb検索76693227-6d1e-45bf-9de0-c269b458b639はメタデータのみで画像確認の証拠ではない。固定settingsソースと実画面を基準としレポート生成なし。

機能内部の日本語直書き、中国語の初期説明・韓国語の初期会話名、backend同期は残る。入力された中国語／韓国語は意図的に保持。生のruntime状態・システムメニュー・VoiceOver・全21状態も未完了。私的V1ディスクに比較用guest uploadを保持し、個別削除・ハッシュ未計測。参照コンテナ／ネットワーク・所有host一時ファイルは削除。クラウド通信なし。カーネル信頼性・アプリ全体の完成は未証明。


CI互換修正:40110609236でCIのnative SwiftPMがraw xcstringsをコピーしキーを返す実失敗を確認。初期ローカルincrementalの未確定原因とは別。e3b4874 RED3→3025b1b exporter3件・Python全52件・cold native-builderカタログ5件GREEN。原本から生成したUTF8 plistをコミットしrawをexclude、両方式でen/ja.lprojをprocess。--checkをCI／アプリbuildの必須検査へ追加。stdlib traceでexporter行94.6%。Swift234件中233成功・AX1スキップは維持。最終署名3025b1bの同梱リソースを検証。画像は5a66610のままで、既記録の名称6修正以外は同じ文言。CI再試行成功前にCI合格と報告しない。
