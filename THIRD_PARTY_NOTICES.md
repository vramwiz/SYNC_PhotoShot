# 第三者コンポーネントと移植元

## SYNC_Mine / スマホ描画

- 出典：[vramwiz/SYNC_Mine](https://github.com/vramwiz/SYNC_Mine)
- 表示：Copyright (c) 2026 VRAMの魔術師
- 条件：GNU General Public License v3。本文：[LICENSE.SYNC_Mine.txt](Source/Lib/Smartphone/LICENSE.SYNC_Mine.txt)
- 対象：`Source/Lib/Smartphone/SYNC_SmartphoneRenderer.pas`
- 抽出元：`Source/Common/Render/SYNC_MINE_Renderer.pas`
- 変更：会話モデル・UI 依存を除去、汎用 API 化、画面画像入力、インスタンス単位の GDI+ 管理など。抽出・統合は 2026-11-09。
- 元プロジェクトの ColorPicker、会話 UI、キャラアイコン等を本部品が含むという意味ではありません。

## SYNC_Nicomea / プロジェクトと登録基盤

- 参考元：SYNC_Nicomea の Delphi プロジェクト、SDK 型、フィルターテーブル登録基盤。
- 確認した参考元の LICENSE：GNU GPL v3。上記 GPL 本文と同じ条件の文書です。
- 対象：`SYNC_PhotoShot.dpr / .dproj` の基盤、`AviUtl2FilterTypes.pas`、`PluginFilterTable.pas` 等の移植部分。
- PhotoShot 用の名称、参照、登録項目、必要な API と配置先を適応しています。
- ビルド後イベントの一行ずつの記述方式は、ユーザー作成の Syncroh2_Extension2 を参考にしています。

## 旧版の MP3 デコーダー

旧版で使用したCC0の復号コアとMITの統合コードの来歴は、ソースリポジトリに保存しています。
[旧版のMP3デコーダー文書](https://github.com/vramwiz/SYNC_PhotoShot/tree/main/ThirdParty/MP3Decoder)

## AviUtl2 SDK

- AviUtl ExEdit2 Plugin SDK、Copyright (c) 2025 Kenkun。
- 手元の SDK license.txt は MIT。原文を [LICENSE.AviUtl2-SDK.txt](ThirdParty/LICENSE.AviUtl2-SDK.txt) に保持しています。
- SDK の型と ABI を参照して Delphi 定義を実装しています。SDK の許諾と AviUtl2 本体の配布条件は別です。本体は同梱しません。

## 実行・開発基盤

Delphi RTL と Windows GDI+ を使用します。各製品の利用・再配布条件に従ってください。Delphi や Windows 自体のライセンスをこのプロジェクトで変更・付与するものではありません。

## 音源と画像

現行版のシャッター音は初期化時にプログラムで合成します。合成音やリポジトリに保管する素材の取り扱いは [LICENSE.md](LICENSE.md) を参照してください。
