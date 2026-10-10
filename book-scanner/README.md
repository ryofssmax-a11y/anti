# ブックスキャナ(PWA)

カメラアームで固定したスマホ/PCのカメラで本をめくりながら連続撮影 → 補正 → 1つのPDF → Google Driveへ保存。NotebookLMのソースにそのまま使えます。依存ライブラリなし。

## 使い方
1. `book-scanner/` を HTTPS で配信(カメラはHTTPS必須。`localhost`はOK)。例: `npx serve book-scanner`、GitHub Pages など。
2. 「カメラ開始」→ 本をカメラに映す。「自動撮影」ONなら、ページをめくって手を離し約0.7秒静止すると自動で撮影。
3. 画質補正は白黒(おすすめ)/2値/カラー。不要なページはサムネの×で削除。
4. 「PDFを保存」で端末へ、「Google Driveに保存」で `BookScans` フォルダへ。
5. NotebookLMで「ソースを追加 → Googleドライブ」から選択。

## Google連携の準備(無料・初回のみ)
1. Google Cloud Console でプロジェクト作成 → 「Google Drive API」を有効化
2. OAuth同意画面を設定(テストユーザーに自分を追加)
3. 認証情報 → OAuthクライアントID(ウェブアプリ)。承認済みJavaScript生成元に配信URLを追加
4. アプリの「設定」にクライアントIDを貼り付け

スコープは `drive.file`(このアプリが作ったファイルのみアクセス)。「OCR済みGoogleドキュメントも作る」をONにすると、DriveがPDFを文字認識してドキュメント化します。

## 制限
ページ輪郭の自動検出・台形補正は未実装です(カメラを真上から固定する前提)。
