# クラウド中継の直接接続を検証

Swiftの処理は、生成済みのプロバイダー要求と、同じホスト名について検査済みの数値IP・443番ポートを組み合わせる。Cの通信処理は、ソケットを開く直前と、要求ヘッダーと本文を送る直前に接続先を照合する。TLS接続専用モードでプロキシとリダイレクトを無効にし、失敗・キャンセル・完了時にハンドルを閉じる。ソケットにはclose-on-execとSIGPIPE抑止を設定した。

macOSのループバック試験では、同じC実装を試験専用の信頼アンカーと組み合わせた。POST本文と分割された応答が一致し、ホスト名不一致・未信頼チェーンのときに接続先へHTTPデータが送られないことを確認した。TLS待ちと応答待ちを中断してソケットを閉じ、応答の上限を超えたデータを拒否した。直接接続に失敗させても設定済みのプロキシへの接続は0件だった。Swiftの試験では接続先の不一致と接続前のキャンセルを確認した。入力と結果は[検証記録](../evidence/llm/cloud-egress-transport-verification.json)を参照。

中間証明書を欠く試験では、ループバックの発行者取得先への接続もAPI要求も0件だった。この観測の範囲は試験に使った証明書と接続先。macOSのSecureTransportによる証明書検証には別の取得ポリシーがあるため、本番の有効化前に取得を明示的に制御し、チェーンが揃った場合の正常接続も対照試験にする。[Appleの証明書検証資料](https://developer.apple.com/documentation/security/sectrustsetnetworkfetchallowed%28_%3A_%3A%29)

オフライン試験は `python3 -m unittest discover -s Tests/GuestArtifactTests -p test_cloud_egress_transport.py -v` と `swift test --filter CloudEgressTransportTests` で再現できる。VMのリスナー、HTTP応答のフレーミング、署名済みVMの隔離、実APIは後続の受入条件。画面変更を伴わないためLazywebは対象外。ホストCIは未検証。
