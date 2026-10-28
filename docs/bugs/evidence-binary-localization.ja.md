# 型付きbinary表示の調査

## 再現・証拠
実capture参照／native比較では固定serverの中国語binary placeholderをprotocol dataとして保持していた。source確認でFindingTrafficViewがraw contentを既存の日英binary案内の下にも表示していた。表示契約の新試験はtext専用表現がなくcompile RED（6d547c4）。wire／sourceと試験契約の証拠であり、解除済み実画面の失敗を観測したとはしない。

## 原因分析
5 Whys：中国語の所有案内が残る→server placeholderを本文表示→raw累積contentを描画→binary型は案内追加とpaging停止にしか使わない→表示用集約が型付きplaceholderと通常textを分けない→翻訳試験にこの型付きケースがなかった。原因は翻訳文不足でなく、presentationが型付きserver案内をpacket textと同じ扱いにしたこと。

Fishbone：protocol＝binary flag＋placeholder、表示＝raw連結、翻訳＝日英案内と重複、データ完全性＝CJK正規表現置換は正しいtextを壊す、試験＝binary pagingはあったが表示分離は未検証。Timeline：実wire証拠148e59c→表示RED6d547c4→修正77f0a7c→workspace／offscreen28GREEN78ef8d2。

## 修正
raw contentを保持し、非binary pageからtextContentを組み立て、既存の日英案内の下に表示。先行text・raw header／DTO／downloadを保持。marker文字列からbinaryを推測せず、型のないraw capture previewは書換えない。

## 検証
新pure4・統合1、全Swift837件（836合格・既存AX1skip）、Python179件。変更source合計LLVM行86.43%、initializer／appendの8regionは全実行。local staged bundleを再build／署名し、旧guest hashを保持。evidence-binary-localization-verification.ja.md参照。実画面と製品全体は未完。

## 再発防止
初回／後続binary・同じmarkerの通常text・FEFF／NFD／CJK・失敗append不変・両wire side・locale時通信なしを維持。server出力の翻訳前に表示と原文の境界を確認し、CJKを一括除去しない。offscreen構築を実画面／keyboard／AX受入としない。
