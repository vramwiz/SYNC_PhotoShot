## 2026-11-09 最新仕様：カメラ内ライブビューのみ

- 撮影結果の写真表示/白枠/準備/キャッシュは廃止。以下の歴史的記録の写真準備手順は現行仕様ではない。
- SourceのPreparation/PreparedStore/HostAPIは現行DPR/DPROJから除外。旧試験の参照資料としてファイルだけ残すが本体へリンクしない。
- 現行DLLは元の3exports。準備用InitializeLogger exportと準備ボタン・自動カーソル移動は撤去。
- 現入力からカメラ内ライブビューを毎フレーム描画。撮影済み画像や編集状態に依存しない。
- 写真結果向けPreview/Hold秒と写真配置設定は削除。残る4時間は0.01秒刻み。
- 本体設定とユーザー音源は保持。規定外プラグイン禁止。最新の機能説明はREADMEを参照。

## 2026-11-09 起動先変更（最新）

ユーザー承認により、Debug/Release の Debugger_HostApplication を
D:\aviutl2_v2.1.16\aviutl2.exe に変更した。
実ファイル内の2.1.16表記と、先にPhotoShot登録成功を確認した隔離本体とのSHA256一致を確認。
.dproj の変更はホスト指定2箇所のみ。他の設定、配備ファイル、ユーザーデータは変更していない。
開いたままのIDEが旧設定を保持している場合は、保存済み作業を保護してプロジェクトを開き直す。
今回の変更後にIDEの実行操作までは確認していない。
以前のエラー発生時に実際に起動していた版は未確定。ユーザーの「はい」は変更への同意として扱った。
バックアップ: Backup/BeforeHost216_20261109_103711。
以下に残る「起動先は2.1.3a」「切替確認待ち」という記録は本変更で解消済み。

## 2026-11-09 追加更新: 行単位ビルドと初期化調査

- ユーザー指定 Syncroh2_Extension2.dproj の方式を採用。
- Debug/Release の DCC_ExeOutput は C:\ProgramData\aviutl2\Plugin\SYNC_PhotoShot\。
- ビルド後は同じフォルダー内で copy、コピー失敗時停止、DLL削除を1行ずつ処理。
  ReleaseはRSM削除も別行。拡張子は .auf2 を維持。
- デバッガホストは参考元どおり両構成 D:\aviutl2_v2.1.3a\aviutl2.exe を維持。
- 検証時は /p:PostBuildEvent= だけでは直接出力を防げない。
  /p:DCC_ExeOutput=検証用の絶対パス も必ず併用して正式配置を保護する。
- 別の試験出力先でビルド後イベントを実行し、auf2生成/DLL削除/Release RSM削除成功。
  正式配置済みファイルのSHA256は変更していない。

初期化エラー:
- 添付は「Failed to register filter plugin. initialize plugin failed」。
- 現コードは2011500未満を拒否。2.1.3aには準備に必要な新SDK APIがないため、
  ガードだけ下げてはいけない。
- 正規2.1.16の隔離実行でHostVersion=2011600、準備/音声初期化、
  Filter table readyを確認。起動した隔離プロセスは終了済み。
- 2.1.3a隔離実行は初期化まで到達せず、実機でのエラー再現は未確定。
  ただし設定先の実バイナリ内文字列も2.1.3aで、IDEからの現設定実行は旧版となる。
- 本体ログは %LOCALAPPDATA%\SYNC_PhotoShot\initialize.log。
  ログには初期化段階とホスト版を残し、ログ失敗はプラグインの成否へ影響させない。
- 最新ホストへデバッガを切り替えるかはユーザー確認待ち。機能を削って旧版に合わせていない。
- 新たな補助/テストプラグインを作成実行していない。正規PhotoShot本体のみを使った。

# SYNC_PhotoShot 作業ノート

## 変更してはいけない前提

- D:\DelphiProg\MyApp\SYNC_Nicomea の .dpr / .dproj を正解としてコピーした構造を保持する。
- 必須の名称・ユニット参照以外の設定値、XML構造、ビルド後イベント方式を勝手に作り直さない。
- 現在は通常 auf2、DLL境界は元と同じ3 exports。追加プラグインを作成・実行しない。
- コピー元、ユーザー Mp3 原本、既存 Setup を変更しない。
- グループ SYNC、名称「写真撮影」、プロジェクト名 SYNC_PhotoShot。
- 現在の機能・操作・制約は README.md を正とする。旧 aux2 方式へ戻さない。

## ビルド

- Delphi 37.0 / Win64。IDEでは SYNC_PhotoShot.dproj を直接開く。
- Debug / Release の両方を検証する。警告・エラー0を原則とする。
- 検証時は /p:PostBuildEvent= で配備を止める。
- 通常ビルド後は元方式でDLLからauf2へコピーし、専用Pluginフォルダーへ配置してDLLを削除する。
- 配備先は C:\ProgramData\aviutl2\Plugin\SYNC_PhotoShot。Debug/Release共通。
- Releaseのデバッガ設定も元の D:\aviutl2_v2.1.3a\aviutl2.exe を維持している。
  本体は2.1.15以降を要求するため、その古いデバッガ先では動作しない。勝手に設定変更しない。
- ユニット追加時は .dpr の in と .dproj の DCCReference を両方更新する。
- IDE設定表示の再確認はまだ行っていない。MSBuild成功だけでIDE表示確認済みとしない。

## ソース配置・コメント

- Source/Common: 描画・データ処理。Source/Plugin/Filter: フィルター固有処理。
- Source/Lib: SDK型・登録基盤・再利用ライブラリ。
- ユニット先頭に目的と責務を書く。公開処理には入出力と重要な副作用を記載する。
- 状態の有効範囲、所有権、保存対象を必要に応じて明記し、単純なコードの言い換えは避ける。
- 日本語を含む .pas / .dpr / .ps1 は UTF-8 BOM、改行 CRLF。
- 約1500行を目安に責務で分割し、フォームの .pas と .dfm は同じ場所に置く。
- UIと描画・データ処理を分離。JSONを将来導入する場合は設定・参照を保存し、素材実体を混在させない。
- SDK型の配置変更は公式ヘッダーと照合。ホスト所有ポインターをcallbackの外へ保持しない。

## 写真・音声

- 標準ボタンから撮影位置へ移動し、対象の通常描画入力だけを採取する。
- 編集callback中に描画完了を待たない。通知は隠しウィンドウへ送る。
- 確定写真がなければ現在映像を写真として代用しない。
- 編集後・プロジェクト再読込後は再準備。完全な編集自動検知を保証しない。
- 4音は音声ユニット専用 .res に内蔵する。主 .res は元のまま。
- 音源変更時のみ Resources/UpdateShutterResources.ps1 を実行する。ビルドイベントへ追加しない。
- MP3デコードは初期化時。音声callback内でファイル読込やデコードをしない。
- 音声は絶対サンプル時刻から計算し、音量は100%を超えない。

## Setup と検証

- SetupはNicomea用旧設定のまま。PhotoShotの配布処理として実行しない。
- 参照元のライセンスと来歴は Source/Lib/Smartphone と ThirdParty/MP3Decoder を参照。
- 実機未確認の点と模擬試験の結果を区別する。追加テスト用pluginは禁止。
- 復元バックアップ: Backup/BeforeReferenceRebuild_20261109_101022。
- 最新の検証記録: Tests/IMPLEMENTATION_STATUS.txt。
## 時間の秒単位化

- 時間6項目は新名「…（秒）」、範囲0～600、step 0.01。旧フレーム名は登録しない。
- 秒値は TPhotoShotSettings の *Seconds、映像演出用 *Frames は ResolvePhotoShotTiming で導出する。
- SDK Scene.Rate/Scale、準備ボタンでは Edit.Info.Rate/Scale を必ず使い、無効値は例外として安全に中止する。30 fps への暗黙 fallback はしない。
- 累積秒境界を Round で量子化して隣接差から段階長を作る。実際の撮影 frame を音声のサンプル開始位置にも使う。
- 準備済み画像の識別情報には Rate/Scale も保存し、fps変更後は写真を失効させる。
- 時間以外の登録名は維持。時間だけは旧保存フレーム値を秒に誤解釈させないため例外的に新名へ変更。
- 旧時間値・中間点の自動移行は行わず、ユーザーが秒で再指定する。実AviUtl2で新名の保存・再読込、旧プロジェクト更新は未検証。