# ライセンス情報

Copyright (c) 2026 VRAMの魔術師

## 本体

PhotoShot 独自コードは GNU General Public License バージョン3（GPL-3.0-only）で公開します。参考元の SYNC_Nicomea および移植した SYNC_Mine のスマートフォン描画コードも GNU GPL v3 の対象です。[GPL v3 本文](Source/Lib/Smartphone/LICENSE.SYNC_Mine.txt)

PhotoShot のソースコードは [vramwiz/SYNC_PhotoShot](https://github.com/vramwiz/SYNC_PhotoShot) で公開しています。

## 外部由来コード

対象・出典・改変内容・本文へのリンクは [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) に整理しています。個別のライセンスは各対象へ適用されます。

## 音源・画像

- 現行のシャッター音4種は、PhotoShot独自のコードがサイン波と固定乱数ノイズから合成します。生成時に使うのはプラグイン内の計算だけです。旧配布版の内蔵音源には、その版の同梱文書に記載された条件が適用されます。
- `Assets/Audio/`：初期の合成音です。同フォルダーの README に生成方法の記録がありますが、それだけで明示的な素材ライセンスが決まるわけではありません。
- `Image/PhotoShot_Test_1920x1080.png`：本作業で用意した AI 生成の確認用画像です。素材の配布条件をコードのライセンスとは別に確定してください。
