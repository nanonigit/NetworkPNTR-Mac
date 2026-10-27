# F5 Findings発展機能の導入

固定版e75ae371ad777ffd1eecdd28d2781a6519b05591を基準とする。通信証跡の追加/閲覧/ダウンロード/編集/並べ替え/削除とversion競合・継承元制限、lineage、再検証の履歴/実行中/開始、deepen、高度なreport、選択/絞込/全件のCSV/JSON/Markdown/ZIP出力が必要。隔離、製品表示の日英限定、ユーザーデータの保持、変更結果不明時の保守的処理を維持する。DTO試験だけで機能を受け入れず、実guest/参照/保存と解除後の実画面・キーボード・VoiceOver比較が必要。

F5aは証跡一覧・詳細・本文の読取を先行する。固定版server/finding_traffic.go、db/finding_traffic.go、web API/typesを参照。finding/binding/contextは正のInt64正規ID、認証付き注入transport、200のみ、4MiB上限、await前後のキャンセル、再試行なし。任意URLや認証情報を渡さない。未知role、FEFF/NFD/CJKを含むnote/header/URL/method/type、opaqueなsource IDを保持し、開いたり実行しない。version/長さ/位置は非負、finding/binding/snapshotの対応とbinding ID重複を検証する。必須配列はnullを空とし欠落を拒否する。

本文は文字数ではなくバイトoffsetで、0<=offset<=next<=total、差分8192以下、truncatedはnext<totalと一致し、続くページは前進する。binary表示や不正UTF8の置換で文字列のバイト数は実バイト消費量と異なるため、同一視しない。詳細の両本文はoffset0でsnapshotの長さとtotalが一致する。応答のowner/binding/offsetを要求と照合する。

順序は固定ソースhash付きデータ→大きなID/未知role/生文字/空null欠落/対応関係/負数overflow/ページ/binary/不正UTF8/query/context/不正入力の送信ゼロ/status/サイズ/キャンセルのRED→実装GREEN→独立レビュー/全体/coverage/署名build/修正HEAD CI。backendのみなのでLazywebは対象外。VMデータや実通信・agent・cloudは変更しない。

F5bで証跡変更と状態/結果不明、F5cでlineage/retest/deepen/report、F5dで本物のbytesを保存する有限download/export能力を実装する。保存先はユーザーが明示選択し任意guest→host書込経路は作らない。後続UIはLazywebと固定browserを使用。空でない証跡/本文の実guestと独立参照・再起動・競合/失敗/掃除も必要。agent開始は専用guest試験で行いhostでは実行しない。F5aだけでF5全体を完了にしない。

F5bの書込は変更可能なFindingRecord、対応するFindingTraffic、任意の所有task文脈を捕捉する。POST追加はtraffic_refsで既知4role・生note・opaqueなsource IDを送り、Go側がIDの空白を除去し重複の最初を使う。noteをtrimせず、固定版が認める重複を拒否しない。PATCH編集はversion/role/note、DELETEはversion、PUT順序はversionと取得済みbindingの全件順列を送る。空一覧の空順列も有効。継承/変更handleなし/別task文脈/非所有bindingは送信前に拒否し、本文はserverと同じ1MiB以下。200・4MiB以下の有効応答・owner一致を要求し、編集/削除/順序ではversionが取得時より進む必要がある。保存後の読戻しに他の変更が挟まるため、増分1だけとは制限しない。追加では既存snapshotならversionが変わらず、新規挿入の証明とはしない。送信後の失敗は型付きエラーのまま自動再送せず、409も中国語/韓国語の本文ではなくHTTP statusで区別する。失敗や後の読取だけで保存有無を断定しない。UI統合前には所有権・停止/reset・捕捉した不明回の確認・競合再読取・書込ブロックを状態層に実装する必要があり、書込契約試験だけでは達成しない。

追加応答も取得時version以上を要求する。変更なしの同値を認めても逆行は認めない。レビューによるRED/GREENはbugs/findings-bind-version.ja.mdを参照。
