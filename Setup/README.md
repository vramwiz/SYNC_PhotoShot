# 写真撮影（SYNC_PhotoShot）

カメラを構え、シャッターを切る演出を加えるAviUtl2用フィルタープラグインです。
Windows 64bit / AviUtl2 2.1.15以降を対象とします。

## インストール・更新

1. AviUtl2を終了します。
2. `SYNC_PhotoShot.zip` を展開し、中の `SYNC_PhotoShot` フォルダーを `C:\ProgramData\aviutl2\Plugin` へコピーします。
3. AviUtl2を起動し、対象映像に「SYNC」グループの「写真撮影」を追加します。

更新も同じ場所へ上書きします。シャッター音はプラグインに内蔵しているため、音源ファイルを別に配置する必要はありません。

## 使い方

1. カメラ種類と位置・倍率・角度、本体・枠色を設定します。
2. 「撮影前」「撮影中」「撮影」で演出と時間を調整します。
3. 通常どおり再生・シークします。

スマートフォンは縦横表示と立体的なケース、他カメラは全画面ファインダーを表示します。
内部X/Y・ズーム・ぼかし、背景のぼかし・暗さを調整できます。
カメラ内にはその時点の映像をライブ表示します。撮影した写真の保存や写真準備は行いません。

時間は登場・撮影待機・シャッター・退場の4項目で、0～600秒、0.01秒刻みです。
実際のタイミングはシーンfpsに合わせてフレームへ丸めます。旧フレーム指定の時間は自動移行せず、秒で再指定してください。

詳細な機能説明・更新情報: [vramwiz/SYNC_PhotoShot](https://github.com/vramwiz/SYNC_PhotoShot)

## アンインストール

AviUtl2を終了し、このZIPに同梱されたファイルを削除します。
カタログからの削除も同梱ファイルだけを対象とし、後から追加したファイルは削除しません。

## ライセンス・ソース

本体と音源の確認状況は `LICENSE.md`、外部由来コードの出典と適用条件は `THIRD_PARTY_NOTICES.md` を参照してください。
GPL v3、MIT、CC0-1.0の関連文書を元と同じ相対パスで同梱しています。
本体独自部分と内蔵音源の条件は既存文書にある最終確認待ちの状態を維持しています。
ソース公開先: [vramwiz/SYNC_PhotoShot](https://github.com/vramwiz/SYNC_PhotoShot)

## 配布ZIPの作成・カタログ登録（開発用）

1. Delphi / Win64のReleaseをビルドします。既定の入力は `C:\ProgramData\aviutl2\Plugin\SYNC_PhotoShot\SYNC_PhotoShot.auf2` です。
2. `xxhsum.exe` を `Win64\Dependencies\xxHash-0.8.4` またはPATHが通った場所に置きます。別環境では [xxHash公式配布](https://github.com/Cyan4973/xxHash/releases/tag/v0.8.4)を使用してください。
3. `Setup\SYNC_PhotoShot.catalog.json` の `version` 末尾に公開タグと日付を設定します。初期値は `v1.0.0` / `2026-11-15` です。次の版は末尾へ追加します。
4. `Setup\make_release_zip.bat` を実行します。`Setup\SYNC_PhotoShot.zip` を作成し、収録AUF2のXXH3-128をJSONの末尾バージョンへ記録します。
5. 公開するソースをGitHubのタグに保存し、Releaseへ `SYNC_PhotoShot.zip` を添付します。カタログ登録では `SYNC_PhotoShot.catalog.json` を読み込みます。

[カタログの公式テンプレート](https://github.com/Neosku/aviutl2-catalog-data/blob/main/template.json)では画像をカタログ本体から登録します。JSONの `images` は空にしてあり、登録時には `Thumnail\Thumnail.gif` を指定してください。リポジトリ上の実ファイル名もこの大文字・小文字です。

別のReleaseフォルダーやxxhsumを使用する場合:

```powershell
.\Setup\make_release_zip.bat -ReleaseDirectory "D:\Release" -XxhsumPath "D:\Tools\xxhsum.exe"
```

作業ディレクトリに依存せず、バッチのあるSetupフォルダーにZIPを出力します。
バッチは既存AUF2の梱包とローカルJSONのハッシュ更新を行います。ビルド・本体起動・GitHubへの公開は別途行います。
同梱対象を変更するときはスクリプトの `$packageFiles` とJSONの `installer.uninstall` を合わせて変更してください。不一致ならZIPを置き換える前に停止します。

ZIP内は `SYNC_PhotoShot/` の下にAUF2、このREADME、`LICENSE.md`、`THIRD_PARTY_NOTICES.md` と次の文書を収録します。

```text
Source/Lib/Smartphone/LICENSE.SYNC_Mine.txt
ThirdParty/LICENSE.AviUtl2-SDK.txt
ThirdParty/LICENSE.SYNC_RhythmShooter.txt
ThirdParty/MP3Decoder/LICENSE.md
ThirdParty/MP3Decoder/provenance.json
ThirdParty/MP3Decoder/CORE_CHANGES.md
ThirdParty/MP3Decoder/PHOTOSHOT_RESOURCE_CHANGES.md
```

MP3原本、テスト画像、開発用ソース・DCU・DLL、旧Setup設定はZIPへ含めません。
