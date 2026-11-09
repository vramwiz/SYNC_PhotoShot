# SYNC_PhotoShot 作業ノート

## プロジェクトの前提

- Delphi プロジェクト名は SYNC_PhotoShot。AviUtl2 のグループ名は SYNC、プラグイン名は「写真撮影」。
- D:\DelphiProg\MyApp\SYNC_Nicomea のプロジェクトと登録用共通ユニットをコピー元とする。この note.md も同プロジェクトからコピーし、共通のビルド・ソース配置・コメント規則を引き継いだ。
- コピー元は変更しない。PhotoShot はコピー元へのソース参照を持たない。
- ビルド後イベントはコピー元の方式を引き継ぎ、出力名と配置先を PhotoShot 専用に変更する。

## 現状と目的

- 「写真撮影」プラグインを実装するための最小限の骨組み。現在はフィルター登録のみを行い、入力映像を変更せずに通す。
- 撮影演出、設定画面、音声、素材読込は未実装。詳細仕様は後続の依頼で決める。
- Nicomea 固有の広告・ギフト取得、書式記号、文字描画、プレビュー、履歴・レイアウト保存は移植しない。元 note.md の機能説明を PhotoShot の実装済み仕様として扱わない。
- 今回は設定とルールの反映まで。ビルド結果・実機動作は未検証。

## ビルド

- Delphi 37.0、Win64。IDE では `SYNC_PhotoShot.dproj` を直接開き、Debug / Release をそれぞれビルドする。警告・エラーともに 0 を原則とする。
- 現段階ではユーザー指定によりビルド・起動・配備を行わない。以下は今後の手順であり、今回の作業では未実行。ビルドすると後述の自動配備も実行される。
- プロジェクトのルートで次を実行する。

```powershell
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_PhotoShot.dproj /t:Build /p:Config=Debug /p:Platform=Win64'
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_PhotoShot.dproj /t:Build /p:Config=Release /p:Platform=Win64'
```

## ビルド後イベントとプロジェクト登録

- AviUtl2 プラグインの配置処理は、Delphi IDE のプロジェクトオプションにある「ビルド後イベント」に直接記述する。Debug / Release の両方で、`copy /Y` により DLL からローカルの `.auf2` を作成し、配置先へコピーする。両方のコピーが成功した後に `del /Q` で中間 DLL を削除する。Release では RSM も削除する。
- SYNC_PhotoShot の配置先は `C:\ProgramData\aviutl2\Plugin\SYNC_PhotoShot`。ローカルの成果物は `Win64\Debug\SYNC_PhotoShot.auf2` と `Win64\Release\SYNC_PhotoShot.auf2`。Debug と Release は同じ配置先にコピーされる。
- ユニットを追加したら、`.dpr` の `in` 指定と `.dproj` の `DCCReference` を両方更新する。フォームやフレームの IDE メタデータも対応させる。

## ソース配置

- `Source/Common` には、描画やデータ処理などの共通処理を機能別に置く。
- `Source/Plugin/Filter` には、AviUtl2 のコールバックや設定画面など、プラグイン固有の処理を置く。
- `Source/Lib` には、AviUtl2 SDK の型定義やフィルターテーブルの登録処理など、共通基盤を置く。

## コメント・分割・文字コード

- ユニット先頭に目的と責務を書く。公開処理には入出力と重要な副作用を記載し、状態の有効範囲、所有権、保存対象を必要に応じて明記する。コードをそのまま言い換えるコメントは避ける。
- 日本語を含む `.pas`、`.dpr`、Windows PowerShell 用の `.ps1` は UTF-8 BOM 付きとし、改行は CRLF とする。
- 1 ユニットは約 1,500 行を目安に責務で分け、関連ユニットは機能別フォルダーに置く。フォームの `.pas` と `.dfm` は同じフォルダーに置く。
- フォームは操作と画面状態を担当する。機能追加時は JSON の検証・解析、同期計算、描画をそれぞれの処理側に置く。JSON を導入する場合は設定値と素材の参照を保存し、素材の実データは埋め込まない。現在はフォーム・JSON 保存・同期計算・描画処理を未実装。
- AviUtl2 SDK 型の順序・サイズ・配置を変える場合は、公式 SDK の定義と照合する。

## 配布用 Setup の扱い

- 既存の Setup フォルダーは変更しない。中のスクリプト・README・SYNC_Nicomea.catalog.json は Nicomea 用のままであり、PhotoShot の配布処理として実行しない。
- IDE ビルド後イベントは PhotoShot 専用で、既存 Setup を呼び出さない。
- 配布作業を行う段階で、Setup の製品名・入力ファイル・出力先・カタログを別途 PhotoShot 用に移植し、旧製品を上書きしないことを確認する。

## スマホ描画ライブラリ

- SYNC_Mine からスマホ枠の描画・縦横サイズ・配置・透明面生成を抽出し、Source/Lib/Smartphone/SYNC_SmartphoneRenderer.pas に格納した。
- .dpr と .dproj に登録済み。Mine の会話処理・UI・キャラ資産・外部ライブラリは含めない。
- 使い方・寿命・ライセンスは Source/Lib/Smartphone/README.md を参照。
- 現在はライブラリの組込みまで。ホスト映像への合成、パラメータ、撮影演出は未接続で、フィルターは従来どおり映像を変更しない。
- ビルド・動作検証・配備は未実施。
