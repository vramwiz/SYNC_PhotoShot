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

## MP3 デコーダー

### 復号コア

- 上流：[gustavoeenriquez/delphi-libraries](https://github.com/gustavoeenriquez/delphi-libraries)
- 元実装：[lieff/minimp3](https://github.com/lieff/minimp3)
- 条件：CC0 1.0 Universal。[CC0 原文](https://creativecommons.org/publicdomain/zero/1.0/legalcode)
- 対象：`Source/Lib/Audio/Core/` の 6 ユニット。SYNC_RhythmShooter 経由で取得。
- 上流コミット：`849dbaf1892486a6dc5f1ebb555c949a6c4dd4d9`
- 保持文書：[上流 LICENSE.md](ThirdParty/MP3Decoder/LICENSE.md)、[provenance.json](ThirdParty/MP3Decoder/provenance.json)、[CORE_CHANGES.md](ThirdParty/MP3Decoder/CORE_CHANGES.md)。
- 保持した上流 LICENSE はライブラリ集全体の文書です。そこで挙げられた Opus / G.729 / PDF 等を PhotoShot が含むことを示すものではありません。

### SYNC_RhythmShooter 由来の統合コード

- 出典：[vramwiz/SYNC_RhythmShooter](https://github.com/vramwiz/SYNC_RhythmShooter)
- 表示：Copyright (c) 2026 VRAMの魔術師
- 参考元プロジェクトの条件：MIT。本文：[LICENSE.SYNC_RhythmShooter.txt](ThirdParty/LICENSE.SYNC_RhythmShooter.txt)
- 対象：`Source/Lib/Audio/MP3Decoder.pas` など参考元から持ち込んだ統合部分。コアの CC0 を変更しません。
- PhotoShot では借用ストリームからの復号を追加し、専用ラッパーから埋込リソースを読み込みます。
- 変更記録：[PHOTOSHOT_RESOURCE_CHANGES.md](ThirdParty/MP3Decoder/PHOTOSHOT_RESOURCE_CHANGES.md)。
- FFmpeg は実行時依存でも同梱コンポーネントでもありません。

## AviUtl2 SDK

- AviUtl ExEdit2 Plugin SDK、Copyright (c) 2025 Kenkun。
- 手元の SDK license.txt は MIT。原文を [LICENSE.AviUtl2-SDK.txt](ThirdParty/LICENSE.AviUtl2-SDK.txt) に保持しています。
- SDK の型と ABI を参照して Delphi 定義を実装しています。SDK の許諾と AviUtl2 本体の配布条件は別です。本体は同梱しません。

## 実行・開発基盤

Delphi RTL と Windows GDI+ を使用します。各製品の利用・再配布条件に従ってください。Delphi や Windows 自体のライセンスをこのプロジェクトで変更・付与するものではありません。

## 音源と画像

コードのライセンスだけでは素材の再配布許諾を証明できません。`Mp3/` と内蔵音源、暫定合成音、AI 生成画像の確認状況は [LICENSE.md](LICENSE.md) を参照してください。
