# SYNC_PhotoShot 作業ノート

## プロジェクトの前提

- Delphi プロジェクト名は SYNC_PhotoShot。AviUtl2 のグループ名は SYNC、プラグイン名は「写真撮影」。
- D:\DelphiProg\MyApp\SYNC_Nicomea のプロジェクトと登録用共通ユニットをコピー元とする。この note.md も同プロジェクトからコピーし、共通のビルド・ソース配置・コメント規則を引き継いだ。
- コピー元は変更しない。PhotoShot はコピー元へのソース参照を持たない。
- ビルド後イベントはコピー元の方式を引き継ぎ、出力名と配置先を PhotoShot 専用に変更する。

## 現状と目的

- 制作指示書 Specification.txt に基づく開発版。実装範囲と未解決事項は README.md を正とする。
- 事前レンダリングによる写真準備を実装した。実機の描画受付・画像採取と単体音声出力は未確認。模擬試験だけで実機対応済みとしない。
- 制作開始の指示により検証ビルドへ進んだ。検証時は /p:PostBuildEvent= で自動配備を止める。

## ビルド

- Delphi 37.0、Win64。IDE では `SYNC_PhotoShot.dproj` を直接開き、Debug / Release をそれぞれビルドする。警告・エラーともに 0 を原則とする。
- 制作段階では Debug / Release を検証する。通常ビルドは後述の自動配備も実行するため、検証時には /p:PostBuildEvent= を付けて止める。
- プロジェクトのルートで次を実行する。

```powershell
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_PhotoShot.dproj /t:Build /p:Config=Debug /p:Platform=Win64'
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_PhotoShot.dproj /t:Build /p:Config=Release /p:Platform=Win64'
```

## ビルド後イベントとプロジェクト登録

- AviUtl2 プラグインの配置処理は、Delphi IDE のプロジェクトオプションにある「ビルド後イベント」に直接記述する。Debug / Release の両方で、`copy /Y` により DLL からローカルの `.aux2` を作成し、配置先へコピーする。現在の開発版では中間 DLL を検証用に残す。Mp3 の4音を専用フォルダーへコピーし、旧auf2がある配備先では重複登録を防ぐため停止する。
- SYNC_PhotoShot の配置先は `C:\ProgramData\aviutl2\Plugin\SYNC_PhotoShot`。ローカルの成果物は `Win64\Debug\SYNC_PhotoShot.aux2` と `Win64\Release\SYNC_PhotoShot.aux2`。Debug と Release は同じ配置先にコピーされる。
- ユニットを追加したら、`.dpr` の `in` 指定と `.dproj` の `DCCReference` を両方更新する。フォームやフレームの IDE メタデータも対応させる。

## ソース配置

- `Source/Common` には、描画やデータ処理などの共通処理を機能別に置く。
- `Source/Plugin/Filter` には、AviUtl2 のコールバックや設定画面など、プラグイン固有の処理を置く。
- `Source/Lib` には、AviUtl2 SDK の型定義やフィルターテーブルの登録処理など、共通基盤を置く。

## コメント・分割・文字コード

- ユニット先頭に目的と責務を書く。公開処理には入出力と重要な副作用を記載し、状態の有効範囲、所有権、保存対象を必要に応じて明記する。コードをそのまま言い換えるコメントは避ける。
- 日本語を含む `.pas`、`.dpr`、Windows PowerShell 用の `.ps1` は UTF-8 BOM 付きとし、改行は CRLF とする。
- 1 ユニットは約 1,500 行を目安に責務で分け、関連ユニットは機能別フォルダーに置く。フォームの `.pas` と `.dfm` は同じフォルダーに置く。
- フォームは操作と画面状態を担当する。機能追加時は JSON の検証・解析、同期計算、描画をそれぞれの処理側に置く。JSON を導入する場合は設定値と素材の参照を保存し、素材の実データは埋め込まない。本体は専用フォーム・JSON 保存を使わず、標準パラメータと純粋なフレーム計算を使用する。
- AviUtl2 SDK 型の順序・サイズ・配置を変える場合は、公式 SDK の定義と照合する。

## 配布用 Setup の扱い

- 既存の Setup フォルダーは変更しない。中のスクリプト・README・SYNC_Nicomea.catalog.json は Nicomea 用のままであり、PhotoShot の配布処理として実行しない。
- IDE ビルド後イベントは PhotoShot 専用で、既存 Setup を呼び出さない。
- 配布作業を行う段階で、Setup の製品名・入力ファイル・出力先・カタログを別途 PhotoShot 用に移植し、旧製品を上書きしないことを確認する。

## スマホ描画ライブラリ

- SYNC_Mine からスマホ枠の描画・縦横サイズ・配置・透明面生成を抽出し、Source/Lib/Smartphone/SYNC_SmartphoneRenderer.pas に格納した。
- .dpr と .dproj に登録済み。Mine の会話処理・UI・キャラ資産・外部ライブラリは含めない。
- 使い方・寿命・ライセンスは Source/Lib/Smartphone/README.md を参照。
- 現在は本体描画器へ接続済み。カメラとライブビューはホスト入力へ合成する。静止写真は標準の「写真を準備」ボタンで事前取得する。SDKからの非同期完了を待って対象入力のみを確定する。
- 単体・統合ビルド試験を実施。AviUtl2 実機への配備・動作検証は未実施。

## 音声

- MP3 は Source/Lib/Audio の純 Delphi デコーダーで初期化時に読み込む。音声コールバック中のファイル読込・デコードは禁止。
- サンプル時刻から毎回計算し、再生ヘッドや再生済みフラグを持たない。音量は原音を超えて増幅しない。
- Mp3 フォルダーのユーザー提供4音を同梱する。元ファイルは変更せず、DLL配下の Mp3 に同名コピーする。仮合成音は使用しない。

対応本体の下限は AviUtl2 2.1.15（RequiredVersion=2011500）。userdata ABI のため旧版は初期化時にも拒否する。

## 写真準備の運用と検証範囲

- 単一 aux2 がフィルターを登録する。追加補助プラグインを作成・実行しない。旧auf2との二重配置を禁止する。
- 編集callback内で画像完了を待たず、通知ダイアログも開かない。要求と通知は隠しメッセージ配送に送る。開始処理中もbusyを保持する。
- UPDATE_OBJECT、シーン変更、ロード、キャッシュ破棄は全写真を無効化する。写真はメモリだけに保持し、再度開いた場合は再準備する。
- 現在の検証は独立EXEと模擬SDKまで。指定外のテストプラグイン検証は中止・無効化済み。実機動作は未確認として扱う。
