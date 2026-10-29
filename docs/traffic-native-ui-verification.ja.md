# ネイティブ通信履歴の操作画面の検証

読取・検索・ソート・ページ移動・host選択・rawプレビュー・削除確認を実装し、RootViewから認証付きguest clientとウィンドウ保持モデルへ接続した。対応表はin_progressで、完了ではない。finding紐付け、blob原本保存拡張、ソート設定保存、実VM／ブラウザ／画面／releaseの条件は残す。

配置は固定e75ae371のTrafficを基準にした。Lazywebの証拠・出典はtraffic-native-ui-design.ja.mdに記録：関連する画面metadataは中程度の参考で、画像自体の確認ではない。取得したClarify指針を常設ラベル、削除の対象と影響、完結した回復文へ反映した。自前59ラベルは英日対応し、packet／host／URL／CJK／FEFF／NFDは原文のまま。Host補完は表示だけで、固定ブラウザ関数から得た合成22ケースとネイティブのUTF8が一致した。関数比較であり、実ブラウザ描画や操作全体の比較ではない。

TDD：0b39c47未実装コンパイルRED→710ce7aの7件GREEN→2438963の承認／複数行Host実RED→c752cb9所有権契約／oracle→5ca6471の9件GREEN→1360bf5確認情報保持RED→8df1796プレビュー／削除競合RED→361c471全916GREEN（915成功／既存AX1スキップ）→912e5e2選択項目試験・最終全917Swift（916成功／既存AX1スキップ）。最初の全試験は古い一覧期待値1件が失敗した。修正ではtraffic=in_progressを明示し、他のpendingと21機能／27ページ／243ハンドラーは維持した。読取専用レビューで修正範囲に具体的な残件はない。証拠／5Whys／Fishbone／Timelineと回帰予防はbugs/traffic-native-ui英日版を参照。

12件の画面／Binding試験はバイトで異なるhost、旧lease／query所有権／preview更新番号／確認ID、未反映入力中の承認、固定確認と再実行拒否、保留書込みとreset後の情報消去、プレビュー操作ゲート、選択タグと固定GET要求を扱う。英日・light/dark・幅900/1440の非表示画面、preview／確認のレイアウト自体では通信やclipboard変更が発生しない。実マウス／キーボード／VoiceOver／root起動の試験ではなく、既存の外部アクセシビリティ確認のスキップも残る。

最終ローカル試験は上記917Swiftと179Python、固定一覧と翻訳出力も成功。LLVM帰属行エントリーはBindings88/89（98.88%）、Presentation42/42（100%）、ScreenModel342/351（97.44%）、TrafficView553/745（74.23%）。4つのTrafficファイル合計は1025/1227（83.54%）で、RootViewは別に0/337、合計には含めない。Observation／genericの対応付けで物理行が重複するため、分岐／実イベント／root起動／実時間／backend効果／製品全体の受入の証拠ではない。view／popover／詳細検索とrootの不足を明示して維持する。

段階ビルドと厳密署名が成功し、同梱manifest/kernel/initramfs/systemハッシュが従来プロファイルと一致した。起動、他の場所へのインストール、候補昇格、実サーバー削除、実provider接続は行っていない。evidence/traffic/native-ui-verification.jsonとrequest-host-oracle.jsonを参照。Mac解除は後回しのままで再依頼していない。TR3–TR5、以前のFindings追加操作、21操作、既定kernelの信頼性／昇格、クラウド／harness／releaseは未完了。Hosted CIも未確認で公開に[skip ci]を使う。
