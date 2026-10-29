# Traffic状態lifecycleの調査

## 再現・証拠
fixture注釈とObservation複数宣言のcompile不備を修正し、missing-type RED011e54bをbehavior失敗と区別した。初回13件の1失敗は初期nil receipt代入前にobserverを張った試験timing不備で、stub dispatch後に移して到着境界を明確化（1f5dd1f）。実negativeではreset後query残留とindex利用不可での回復を8assertion（cbf26a7）、busy解除時の同期離脱後に成功を返す問題を1失敗（4b10089）で再現。ローカルの決定的state／transport fixtureであり、VM／実画面の観測失敗ではない。

## 原因分析
5 Whys：private filterが残る→resetがread／選択のみ消しqueryを消さない→queryを持続navigation状態と扱う→認証resetと閲覧保持を十分分離しなかった。利用不可で回復できる→HTTP／decode成功とfresh flagだけで判断→正しいunavailable sentinelを除外しなかった。旧ownerへ成功が返る→return値確定後のdeferがobservable write gateを解除→その公開で同期stop／reset→最後の公開より前に所有検証が済んでいた。非同期成功だけでなく意味的境界の照合が必要だった。

Fishbone：privacy＝適用filter対新session、可用性＝unavailable対empty、競合＝willSet再入／defer cleanup、scope＝byte identity／固定request対live draft、試験＝observer timing／compile REDとbehavior、受入＝pure state対実VM／UI。

## 修正・履歴
888736c compile失敗→契約修正RED011e54b→実装23eb4d0→observer修正13GREEN1f5dd1f→query／利用不可REDcbf26a7→15GREEN57c28fa→18GREENd68b977→解除RED4b10089→cleanup後所有照合19GREEN738636c→cancel20GREEN91f29fa→遅いdetail21GREEN10227cd。teardown時query消去、利用可能な一式fresh回復、write gateを明示解除して最後のowner／session／activity／cancelを再検証。早期exitのfallback cleanup、旧owner guard、reset優先、固定requestも維持。

## 検証
state21件と全Swift870件（869合格・既存AX1skip）合格。TrafficStore357/358・prepare版TrafficService64/64 LLVM行を実行。review残存blockerなし。Python／build／署名とartifactはtraffic-state-verification／evidenceへ記録。実backend破壊操作・外部target・UI操作・永続window間／process journalを実施済みとはしない。

## 再発防止
失敗したreset／unavailable／解除の各試験、host／settings部分失敗、古いowner／revision、処理中reset、dispatch前stop、dispatch後cancel、byteで区別する跨ぎ選択、held detail／pageを保持。不明操作の再送やHTTP失敗のrollback推測をしない。fresh readは明示ackを可能にするだけで、cleanup公開後に旧ownerへ成功を返さない。実VM／source／UI・製品全体gateは別途。
