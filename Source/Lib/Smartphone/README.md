# スマホ描画ライブラリ

SYNC_Mine / Source/Common/Render/SYNC_MINE_Renderer.pas から、スマホ外形の描画・縦横サイズ・配置計算・角丸・透明面生成を抽出しました。
元の会話モデル、会話 UI、アイコン、画像読込、設定画面、AviUtl2PluginLib への参照は含みません。
Delphi 標準 RTL と Windows GDI+ だけに依存します。

## API

- TSmartphoneRenderer.Create / Free: GDI+ と描画面の寿命を管理。
- SmartphoneSize: 縦 420 x 820、横 820 x 420。
- SmartphoneBounds: 映像中心からの位置と倍率から描画矩形を作成。
- Draw: 既存の TGPGraphics にスマホを描画。画面に渡す画像は角丸領域へ伸縮。
- Draw の末尾引数 RaisedCase=True で、指定色に追従する保護ケースの厚み・側面ボタン・縁の反射・ガラスの段差を描画します。既定値はFalse。PhotoShotのスマートフォンだけで有効にし、共通枠を使う他カメラには適用しません。
- RenderSurface: 映像内の必要範囲だけを透明 PixelFormat32bppPARGB で生成。

立体ケースは従来の外形サイズ内へGDI+の角丸とグラデーションで描きます。
画面・撮影領域の座標を維持し、ケース用の画像素材やぼかし用の追加bitmapは作成しません。

同一インスタンスを並行利用しないでください。画面画像の所有権は呼出側にあります。
RenderSurface の戻り値は描画器が所有し、次回呼出しで変更または再確保します。
他の GDI+ オブジェクトも使う場合は、描画器より先に破棄するか、呼出側で別途 GDI+ の寿命を管理してください。

## 利用例（後続実装用）

~~~pascal
Renderer := TSmartphoneRenderer.Create;
try
  Bounds := SmartphoneBounds(1920, 1080, 0, 0, 0, 1.0);
  // Target は呼出側の TGPGraphics。ScreenImage は借用する画像、または nil。
  Renderer.Draw(Target, Bounds, 0, $FF303840, $FFFFFFFF, ScreenImage);
finally
  Renderer.Free;
end;
~~~

AviUtl2 用には Bounds と映像矩形の交差範囲を RenderSurface に渡し、
返る PARGB 画像をホスト画像へ合成する処理を別途実装します。
本ライブラリは SDK 型やホストコールバックを変更しません。
現在の PhotoShot フィルターは本ライブラリを統合してスマホを描画します。
本体のビルドと模擬 SDK 描画検証を実施しています。実ホストでの表示・アルファ合成を含む全組合せの検証完了を意味しません。現在の確認範囲はルートの README.md を参照してください。

## 出典とライセンス

MINE（SYNC_MINE）: Copyright (c) 2026 VRAMの魔術師
コピー元の THIRD_PARTY_NOTICES.md に従い、抽出元のコードは GPL-3.0 です。
全文を LICENSE.SYNC_Mine.txt に保持しています。
改変内容: 会話依存を除去、汎用 API 名へ変更、画面画像を受け取る機能を追加、
GDI+ 寿命をインスタンス単位へ変更、描画面割当失敗と自己参照を検査、
PhotoShot用に選択可能な立体保護ケースの陰影と側面ボタンを追加。
配布時にはこの由来とライセンスを維持し、組み合わせた配布物の条件を確認してください。
