unit SYNC_PhotoShot_Parameters;

// ホスト標準パラメータの登録と現在値のスナップショットを担当する。
// 項目本体と列挙名は DLL が所有し、ホストは描画時に Value を設定する。
interface

uses
  SYNC_PhotoShot_Timeline;

// SetupPluginTable 後に一度呼ぶ。項目を登録順に追加し、初期値を設定する。
procedure RegisterPhotoShotParameters;
// 現在のホスト補間値を独立したレコードへコピーする。状態保存や時間補間は行わない。
function ReadPhotoShotParameters: TPhotoShotSettings;

implementation

uses
  System.Math, AviUtl2FilterTypes, PluginFilterTable;

var
  CameraKind, Orientation, Shutter, EnterAnim, ExitAnim, PreviewStyle,
    PreviewAnim: TFILTER_ITEM_SELECT;
  CameraOptions: array[0..4] of TFILTER_ITEM_SELECT_ITEM;
  DirectionOptions: array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  ShutterOptions: array[0..11] of TFILTER_ITEM_SELECT_ITEM;
  AnimationOptions: array[0..7] of TFILTER_ITEM_SELECT_ITEM;
  PreviewOptions: array[0..3] of TFILTER_ITEM_SELECT_ITEM;
  Groups: array[0..6] of TFILTER_ITEM_GROUP;
  Tracks: array[0..22] of TFILTER_ITEM_TRACK;

procedure RegisterPhotoShotParameters;
const
  CameraNames: array[0..3] of PWideChar =
    ('スマートフォン', 'コンパクトデジタルカメラ', '一眼レフ', 'インスタントカメラ');
  ShutterNames: array[0..10] of PWideChar =
    ('なし', '白フラッシュ', '暗転', '軽い画面振動', '円形アイリス', '絞り羽根',
     '横方向に閉じる', '縦方向に閉じる', '二段階で閉じる', '絞り＋フラッシュ', '絞り＋静止画切替');
  AnimNames: array[0..6] of PWideChar =
    ('なし', 'フェード', 'ズーム', 'スライド', '回転', 'ポップ', 'バウンド');
var
  I: Integer;
  S: TPhotoShotSettings;
begin
  S := DefaultPhotoShotSettings;
  for I := 0 to 3 do
  begin
    CameraOptions[I].Name := CameraNames[I];
    CameraOptions[I].Value := I;
  end;
  DirectionOptions[0].Name := '縦向き';
  DirectionOptions[1].Name := '横向き';
  DirectionOptions[1].Value := 1;
  for I := 0 to 10 do
  begin
    ShutterOptions[I].Name := ShutterNames[I];
    ShutterOptions[I].Value := I;
  end;
  for I := 0 to 6 do
  begin
    AnimationOptions[I].Name := AnimNames[I];
    AnimationOptions[I].Value := I;
  end;
  PreviewOptions[0].Name := '全体表示';
  PreviewOptions[1].Name := '白枠付き写真';
  PreviewOptions[1].Value := 1;
  PreviewOptions[2].Name := 'インスタント写真風';
  PreviewOptions[2].Value := 2;
  AddSelect(CameraKind, 'カメラ種類', S.CameraKind, @CameraOptions[0]);
  AddSelect(Orientation, 'カメラ方向', S.Orientation, @DirectionOptions[0]);
  AddSelect(Shutter, 'シャッター演出', S.ShutterEffect, @ShutterOptions[0]);
  AddGroup(Groups[0], 'カメラ本体', 1);
  AddTrack(Tracks[0], 'X', S.X, -32768, 32768, 1);
  AddTrack(Tracks[1], 'Y', S.Y, -32768, 32768, 1);
  AddTrack(Tracks[2], '拡大率', S.Scale, 0, 1000, 0.1);
  AddTrack(Tracks[3], '回転', S.Rotation, -3600, 3600, 0.1);
  AddTrack(Tracks[4], '透明度', 100-S.Opacity, 0, 100, 0.1);
  AddGroup(Groups[1], 'カメラ内部', 1);
  AddTrack(Tracks[5], '内部X', S.InnerX, -32768, 32768, 1);
  AddTrack(Tracks[6], '内部Y', S.InnerY, -32768, 32768, 1);
  AddTrack(Tracks[7], '内部ズーム', S.InnerZoom, 1, 1000, 0.1);
  AddTrack(Tracks[8], '内部ぼかし', S.InnerBlur, 0, 100, 1);
  AddGroup(Groups[2], 'カメラ演出', 1);
  AddSelect(EnterAnim, '登場演出', S.CameraEnter, @AnimationOptions[0]);
  AddSelect(ExitAnim, '退場演出', S.CameraExit, @AnimationOptions[0]);
  AddGroup(Groups[3], '時間設定（フレーム）', 1);
  AddTrack(Tracks[9], '登場時間', S.EnterFrames, 0, 18000, 1);
  AddTrack(Tracks[10], '撮影待機時間', S.WaitFrames, 0, 18000, 1);
  AddTrack(Tracks[11], 'シャッター時間', S.ShutterFrames, 0, 18000, 1);
  AddTrack(Tracks[12], '退場・切替時間', S.ExitFrames, 0, 18000, 1);
  AddTrack(Tracks[13], 'プレビュー登場時間', S.PreviewFrames, 0, 18000, 1);
  AddTrack(Tracks[14], 'プレビュー保持時間', S.HoldFrames, 0, 18000, 1);
  AddGroup(Groups[4], 'プレビュー設定', 1);
  AddSelect(PreviewStyle, 'プレビュー方式', S.PreviewStyle, @PreviewOptions[0]);
  AddSelect(PreviewAnim, 'プレビュー演出', S.PreviewEnter, @AnimationOptions[0]);
  AddTrack(Tracks[15], 'プレビューX', S.PreviewX, -32768, 32768, 1);
  AddTrack(Tracks[16], 'プレビューY', S.PreviewY, -32768, 32768, 1);
  AddTrack(Tracks[17], 'プレビュー拡大率', S.PreviewScale, 0, 1000, 0.1);
  AddTrack(Tracks[18], 'プレビュー回転', S.PreviewRotation, -3600, 3600, 0.1);
  AddGroup(Groups[5], '背景設定', 1);
  AddTrack(Tracks[19], '背景ぼかし', S.BackgroundBlur, 0, 100, 1);
  AddTrack(Tracks[20], '背景暗さ', S.BackgroundDark, 0, 100, 0.1);
end;

function ReadPhotoShotParameters: TPhotoShotSettings;
begin
  Result := DefaultPhotoShotSettings;
  Result.CameraKind := CameraKind.Value;
  Result.Orientation := Orientation.Value;
  Result.ShutterEffect := Shutter.Value;
  Result.CameraEnter := EnterAnim.Value;
  Result.CameraExit := ExitAnim.Value;
  Result.PreviewEnter := PreviewAnim.Value;
  Result.PreviewStyle := PreviewStyle.Value;
  Result.X := Tracks[0].Value;
  Result.Y := Tracks[1].Value;
  Result.Scale := Tracks[2].Value;
  Result.Rotation := Tracks[3].Value;
  Result.Opacity := 100-Tracks[4].Value;
  Result.InnerX := Tracks[5].Value;
  Result.InnerY := Tracks[6].Value;
  Result.InnerZoom := Tracks[7].Value;
  Result.InnerBlur := Tracks[8].Value;
  Result.EnterFrames := Round(EnsureRange(Tracks[9].Value, 0.0, 18000.0));
  Result.WaitFrames := Round(EnsureRange(Tracks[10].Value, 0.0, 18000.0));
  Result.ShutterFrames := Round(EnsureRange(Tracks[11].Value, 0.0, 18000.0));
  Result.ExitFrames := Round(EnsureRange(Tracks[12].Value, 0.0, 18000.0));
  Result.PreviewFrames := Round(EnsureRange(Tracks[13].Value, 0.0, 18000.0));
  Result.HoldFrames := Round(EnsureRange(Tracks[14].Value, 0.0, 18000.0));
  Result.PreviewX := Tracks[15].Value;
  Result.PreviewY := Tracks[16].Value;
  Result.PreviewScale := Tracks[17].Value;
  Result.PreviewRotation := Tracks[18].Value;
  Result.BackgroundBlur := Tracks[19].Value;
  Result.BackgroundDark := Tracks[20].Value;
end;

end.
