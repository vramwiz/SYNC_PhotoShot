# SYNC_PhotoShot

AviUtl2 プラグイン「写真撮影」の最小プロジェクトです。

- プロジェクト: SYNC_PhotoShot.dproj / SYNC_PhotoShot.dpr
- プラグイン名: 写真撮影
- グループ: SYNC
- 対象: Win64
- 最終成果物: .auf2（ビルド後イベントで中間 DLL から作成）

SYNC_Nicomea.dpr とプロジェクト設定を基に、登録用の共通ユニットだけをコピーしています。
現段階は映像を変更しないフィルターの骨組みで、撮影演出、設定画面、音声、素材読込は未実装です。
元プロジェクトへのソース参照はありません。ビルド後イベントは PhotoShot 専用に移植済みです。
今後ビルドすると DLL から .auf2 を作成し、C:\ProgramData\aviutl2\Plugin\SYNC_PhotoShot に自動配備します。
ビルド手順・コメント・ソース配置・文字コードの共通ルールは note.md を参照してください。

ユーザー指定によりビルド、起動、AviUtl2 への配備は実施していません。
既存の Setup フォルダーは変更していません。そこに残る Nicomea 用の配布設定は現段階では実行対象外です。

## スマホ描画ライブラリ

- SYNC_Mine からスマホ枠の描画・縦横サイズ・配置・透明面生成を抽出し、Source/Lib/Smartphone/SYNC_SmartphoneRenderer.pas に格納した。
- .dpr と .dproj に登録済み。Mine の会話処理・UI・キャラ資産・外部ライブラリは含めない。
- 使い方・寿命・ライセンスは Source/Lib/Smartphone/README.md を参照。
- 現在はライブラリの組込みまで。ホスト映像への合成、パラメータ、撮影演出は未接続で、フィルターは従来どおり映像を変更しない。
- ビルド・動作検証・配備は未実施。
