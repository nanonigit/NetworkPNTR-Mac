# 通信履歴ソート保存の検証

独立したアプリ設定へ、ブラウザ同等の列／方向だけを復元・保存するようにした。基準は固定sort-preference.tsとlocal-storage.client.tsの形式、初期ts/desc、best-effort保存。最初の読取前に復元し、前の書込みが保留なら復元を待って操作や初期順の読取を始めない。stop/resetは一時／非公開状態を消し、非公開情報を含まない選択だけを残す。配置変更やブラウザ保存領域へのアクセスは追加していない。

02441cfは注入未実装のコンパイルRED。0aee4c0で9件中8件が成功し、復元queryの通知中にresetが入ったときの破棄済みlease返却1件を再現した。モデル／queryは消去され元の保存値も未変更。454d398でpolling／return前の所有権確認を追加し9件成功。独立した読取専用レビューも同じ問題を指摘し、修正後の具体的な残件はなかった。5Whys／Fishbone／Timelineと回帰予防はbugs/traffic-sort-preference英日版を参照。

追加9件は正常6組、不正／欠落／旧形式／上限9入力、2項目への正規化、構築時の書込なし、nilで保存無効、原文非保存と再表示、禁止／古い操作、通知中のstop/reset、保留書込み後の最初の読取順と結果不明保持／DELETE1回を検証した。使い捨てUserDefaults suiteのみを使い、本番アプリ／ブラウザ領域は変更していない。全926Swiftは925成功・既存の外部アクセシビリティ確認1件スキップ。179Python、翻訳出力、21/27/243の一覧も成功。LLVM帰属行は設定23/24（95.83%）、モデル385/394（97.72%）、合計408/418（97.61%）。RootViewは別に0/337で合計に含めず、分岐／実画面／OS権限エラー／root起動の証明ではない。

段階ビルドと厳密署名が成功し、同梱manifest/kernel/initramfs/systemが従来プロファイルと一致した。起動、他の場所へのインストール、候補昇格、実provider接続、実VM変更は行っていない。証跡はevidence/traffic/sort-preference-verification.json。今回閉じるのはソート保存のソフトウェア契約のみ。TR3の紐付け／blob、実アプリ再起動／domain、VM／元版／画面／keyboard／VoiceOver／複数窓、既存のkernel／4社／harness／releaseは未完了。HostedCIも未確認で公開に[skip ci]を使う。
