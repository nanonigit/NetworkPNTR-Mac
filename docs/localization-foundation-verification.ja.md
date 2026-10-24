# 言語設定基盤 (L1)

要件・設計・タスク後、766c82dで型未実装RED、690c4e1で5テストGREEN。AppLanguageの保存・通信値はen/jaだけ。OS候補は地域指定を受け付けるがアプリ保存値は正規値のみ。不正・非文字列はOS設定と無関係に英語へ修復。MainActor observableが専用UserDefaultsキーだけを所有し、試験は固有suiteだけを使い終了時に削除。認証・backend状態は読み書きしない。

証拠はevidence/localization/preferences-verification.jsonとpreferences-coverage.json。Swift229件中228成功・既知AX1明示スキップ、Python49成功。追加2ファイルの行・領域100%。読み取りレビュー承認。インスタンス再作成を実アプリ再起動や画面合格には数えない。署名ビルドはビルド検証であり、L2接続までは従来の直書きUIが残る。

MUSUBIリスク分析: 元の言語切替は未存在のため、型未実装REDを既存ランタイムの不具合とは主張しない。5 Whysのリスク連鎖は、他言語表示が残る→非対応localeの保存→backendが多言語許可→native側へ無検証流用できない→専用2ケース型と保存境界が必要。Fishboneはlocale解析、保存優先、actor所有権、suite分離、画面/backend反映。Timelineは実画面混在監査→日英要件→Core RED/GREEN→レビュー→全試験/カバレッジ→署名ビルド。再発防止はwire拒否・不正修復・保存/隔離の試験。UI・カタログ・backend・再起動・全21機能一致は未完了。
