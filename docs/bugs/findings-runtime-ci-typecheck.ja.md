# F4b試験データのコンパイル時間超過

再現・証拠: GitHub Actions40466516578、HEAD184adacf0d70ff41b991a105b6b90609dd20149dの `swift test` コンパイルで失敗。FindingExerciseVerifierTests.objects と FindingReadExerciseWire.init の辞書構築mapが、型推論を制限時間内に終えられませんでした。同じコードのローカル全596試験は成功していました。変更なしの再実行だけで修正済みにはしません。

MUSUBI工程: 失敗HEADのログ取得→2つの式への切分け→固定データと通信形式の確認→型付き試験helperへの置換→正常/破損試験とCIの再検証。製品・SQL・コンパイラ制限は変更しません。5 Whys: CIの型推論が予算超過→辞書/optional/map/三項演算の全体推論→型の境界不足→2箇所で変換を複製→型付き共有処理で再発防止。Fishbone: コンパイラ（推論予算）、データ（異種辞書）、コード（入れ子）、工程（ローカル成功だけでは互換性不十分）。Timeline: ローカルGREEN→CI RED40466516578→型付きhelper→全体試験→修正HEADのCI確認。

修正: FindingExerciseTestDataで行配列と資産辞書を型明示し、ID変換を分割。孤立行のtask_idは通信DTO同様に省略し、資産は固定switchで検証し未知IDを拒否します。破損試験の対象は減らさず、一意なsnake-caseキーを変更します。読取専用レビューで阻害問題はありませんが、CI成功の実測が必要です。
