# Binary preview翻訳の段階検証

78ef8d2時点で、型付きbinary pageのraw累積contentを厳密保持し、表示専用textContentへserver生成placeholderを足さない。既存の英日binary案内と原本保存が唯一の説明になる。通常text中の同じmarker・FEFF／NFD／CJK、先行text page、raw headerは保持。wire／DTO／backend／key・catalog／offset／所有者／download契約は変更していない。captured pickerのraw previewには型付きbinary flagがないため書換えず、残るmarker監査ではserver表示構文と本当のpacket textを区別する必要がある。

新pure4試験はtextContent未実装でRED（6d547c4）、GREEN77f0a7c。新workspace統合78ef8d2でrequest／response両wire page・整合するsnapshot長／hash・raw header・追加page通信なし・英日light／dark offscreen構築時の通信なしを確認。対象28合格。全Swift837件は836合格・既存external AX1skip、Python179合格。baseline21／27／243・localizationも合格したがnative workflow parityは未完。

変更2ファイル合計のLLVM行coverageは605/700（86.43%）：workspace335/338（99.11%）、view270/362（74.59%）。typed previewのinitializer／appendは実行region3/3・5/5。viewの残る操作／lifecycle closureはcoverage済みとせず、branch・製品全体・実画面受入の値でもない。最後のtargetだけの既定JSONでなく、ArtexMacTestsの計測object／profileを使用した。

local app buildの終了成功とstrict codesignを確認。staged bundleに新表示symbolが入り、guest manifest／kernel／initramfs／system hashは従来staged／default成果物と一致した。候補kernel／profileの標準昇格はしていない。app起動・別場所へのinstall、実UI／keyboard／VoiceOver／複数window／保存panel受入は未確認。source／bundle hash等はevidence/findings/binary-localization-verification.jsonに記録。release／kernel／全workflow／4社／harnessは継続。hosted CIは未検証で公開HEADに[skip ci]を付ける。

設計根拠：Lazyweb0.15.14はhealthy、HTTP response binary preview検索は弱い隣接metadata（最上位HTTPie0.385266）で、画像や正確なbinary-previewは確認していない。直接基準は固定source。[Clarify](https://raw.githubusercontent.com/pbakaus/impeccable/main/.claude/skills/impeccable/reference/clarify.md)の指針から、完結した状態／次の操作の翻訳文を一度だけ提示し、重複案内を除いた。design順位や画面比較済みとはしない。原因・回帰はbugs/evidence-binary-localization.ja.md参照。
