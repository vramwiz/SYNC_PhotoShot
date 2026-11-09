# PhotoShot MP3 リソース組込み

ユーザー指定 Mp3 フォルダーの4音を、そのまま専用リソースに埋め込みます。

対象:
Source/Plugin/Filter/SYNC_PhotoShot_Audio.res

このリソースは SYNC_PhotoShot_Audio.pas の {$R SYNC_PhotoShot_Audio.res} からリンクします。
主 SYNC_PhotoShot.res は元の96バイトへ完全復元しており、変更していません。
IDEが主リソースを再生成しても音源は消えません。
dpr/dproj・ビルドイベントを変更せず、追加プラグインも作成していません。

- PHOTOSHOT_SMARTPHONE = スマホ.mp3
- PHOTOSHOT_COMPACT = コンデジ.mp3
- PHOTOSHOT_DSLR = 一眼レフ.mp3
- PHOTOSHOT_INSTANT = インスタントカメラ.mp3

音声ユニットは埋込RCDATAを優先します。欠落時のみ旧 Mp3 フォルダーから互換読込します。
元MP3は変更・再エンコードしていません。元と各リソースのバイト一致、デコードPCM完全一致を確認済みです。

保守:
Mp3音源を更新したときは Resources/UpdateShutterResources.ps1 を明示実行します。
これは専用.resだけを更新し、毎回Backupへ変更前ファイルを保全します。
再実行しても重複追加せず同じSHA256となることを確認済みです。
プロジェクトのビルドイベントからは呼びません。

デコーダー変更:
MP3Decoder.pas に借用 TStream を扱う DecodeMP3Stream を追加。
既存ファイルAPIはファイルを開いて新APIへ委譲します。
MPEG解析・復号・サンプルレート変換アルゴリズムは変更していません。
この1ファイルは初期コピー時のハッシュから変わります。Core6ユニットと参照元は変更していません。
SYNC_PhotoShot_MP3 は Stream / Resource API を追加し、一時ファイルなしで直接デコードします。

検証:
Tests/UserAudio/EmbeddedAudioTests.dpr（通常EXE）に主.resと専用.resをリンク。
元PLATFORMTARGETSが残ること、4音の元MP3一致、file/resource PCM一致を検証済み。
結果: resource-results.txt / resource-build.txt。
本体の全ビルドと配備は親作業で行います。
変更前バックアップ: Backup/AudioResource_20261109_101345。
