unit SYNC_PhotoShot_Parameters;

// ホスト標準パラメータの登録と現在値のスナップショットを担当する。
// 項目本体と列挙名は DLL が所有し、ホストは描画時に Value を設定する。
interface

uses
  SYNC_PhotoShot_Timeline;

// SetupPluginTable 後に一度呼ぶ。項目を登録順に追加し、初期値を設定する。
procedure RegisterPhotoShotParameters;
// 現在のホスト補間値を独立コピーし、Rate/Scale で累積秒境界をフレームへ変換する。
// 時間項目だけは旧フレーム名を使わず（秒）付きの新名。旧保存値の自動移行はしない。
function ReadPhotoShotParameters(Rate, Scale: Integer): TPhotoShotSettings;

implementation

uses
  AviUtl2FilterTypes, PluginFilterTable, SYNC_PhotoShot_Audio;

var
  CameraKind, Orientation, Shutter, EnterAnim, ExitAnim: TFILTER_ITEM_SELECT;
  CameraOptions: array[0..4] of TFILTER_ITEM_SELECT_ITEM;
  DirectionOptions: array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  ShutterOptions: array[0..10] of TFILTER_ITEM_SELECT_ITEM;
  AnimationOptions: array[0..7] of TFILTER_ITEM_SELECT_ITEM;
  EnterAnimationOptions: array[0..9] of TFILTER_ITEM_SELECT_ITEM;
  Groups: array[0..4] of TFILTER_ITEM_GROUP;
  Tracks: array[0..14] of TFILTER_ITEM_TRACK;

procedure RegisterPhotoShotParameters;
const
  CameraNames: array[0..3] of PWideChar =
    ('スマートフォン', 'コンパクトデジタルカメラ', '一眼レフ', 'インスタントカメラ');
  ShutterNames: array[0..9] of PWideChar =
    ('なし', '白フラッシュ', '暗転', '軽い画面振動', '円形アイリス', '絞り羽根',
     '横方向に閉じる', '縦方向に閉じる', '二段階で閉じる', '絞り＋フラッシュ');
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
  for I := 0 to 9 do
  begin
    ShutterOptions[I].Name := ShutterNames[I];
    ShutterOptions[I].Value := I;
  end;
  for I := 0 to 6 do
  begin
    AnimationOptions[I].Name := AnimNames[I];
    AnimationOptions[I].Value := I;
  end;
  // 既存値0..6は不変。追加は7,8に限定し、退場の選択肢は変えない。
  for I := 0 to 6 do EnterAnimationOptions[I] := AnimationOptions[I];
  EnterAnimationOptions[2].Name := 'ズームイン';
  EnterAnimationOptions[7].Name := 'ズームアウト';
  EnterAnimationOptions[7].Value := 7;
  EnterAnimationOptions[8].Name := '起き上がり';
  EnterAnimationOptions[8].Value := 8;
  // 末尾[9]はゼロ初期化されたnull終端を保持する。
  // 保存済みの項目名・数値は保ち、実際の登録順を処理の時系列に合わせる。
  // カメラ共通設定は演出段階から独立させ、先頭へ置く。
  AddGroup(Groups[4], 'カメラ設定', 1);
  AddSelect(CameraKind, 'カメラ種類', S.CameraKind, @CameraOptions[0]);
  AddSelect(Orientation, 'カメラ方向', S.Orientation, @DirectionOptions[0]);
  AddTrack(Tracks[0], 'X', S.X, -32768, 32768, 1);
  AddTrack(Tracks[1], 'Y', S.Y, -32768, 32768, 1);
  AddTrack(Tracks[2], '拡大率', S.Scale, 0, 1000, 0.1);
  AddTrack(Tracks[3], '回転', S.Rotation, -3600, 3600, 0.1);
  AddTrack(Tracks[4], '透明度', 100-S.Opacity, 0, 100, 0.1);

  AddGroup(Groups[0], '撮影前', 1);
  AddSelect(EnterAnim, '登場演出', S.CameraEnter, @EnterAnimationOptions[0]);
  AddTrack(Tracks[9], '登場時間（秒）', S.EnterSeconds, 0, 600, 0.01);

  AddGroup(Groups[1], '撮影中', 1);
  // 現段階の演出はライブビューを表示して構えを維持する。架空の選択肢は追加しない。
  AddTrack(Tracks[10], '撮影待機時間（秒）', S.WaitSeconds, 0, 600, 0.01);
  AddTrack(Tracks[5], '内部X', S.InnerX, -32768, 32768, 1);
  AddTrack(Tracks[6], '内部Y', S.InnerY, -32768, 32768, 1);
  AddTrack(Tracks[7], '内部ズーム', S.InnerZoom, 1, 1000, 0.1);
  AddTrack(Tracks[8], '内部ぼかし', S.InnerBlur, 0, 100, 1);
  AddTrack(Tracks[13], '背景ぼかし', S.BackgroundBlur, 0, 100, 1);
  AddTrack(Tracks[14], '背景暗さ', S.BackgroundDark, 0, 100, 0.1);

  AddGroup(Groups[2], '撮影', 1);
  AddSelect(Shutter, 'シャッター演出', S.ShutterEffect, @ShutterOptions[0]);
  AddTrack(Tracks[11], 'シャッター時間（秒）', S.ShutterSeconds, 0, 600, 0.01);
  RegisterPhotoShotAudioParameter(False);
  AddSelect(ExitAnim, '退場演出', S.CameraExit, @AnimationOptions[0]);
  AddTrack(Tracks[12], '退場・切替時間（秒）', S.ExitSeconds, 0, 600, 0.01);

end;

function ReadPhotoShotParameters(Rate, Scale: Integer): TPhotoShotSettings;
begin
  Result := DefaultPhotoShotSettings;
  Result.CameraKind := CameraKind.Value;
  Result.Orientation := Orientation.Value;
  Result.ShutterEffect := Shutter.Value;
  Result.CameraEnter := EnterAnim.Value;
  Result.CameraExit := ExitAnim.Value;
  Result.X := Tracks[0].Value;
  Result.Y := Tracks[1].Value;
  Result.Scale := Tracks[2].Value;
  Result.Rotation := Tracks[3].Value;
  Result.Opacity := 100-Tracks[4].Value;
  Result.InnerX := Tracks[5].Value;
  Result.InnerY := Tracks[6].Value;
  Result.InnerZoom := Tracks[7].Value;
  Result.InnerBlur := Tracks[8].Value;
  Result.EnterSeconds := Tracks[9].Value;
  Result.WaitSeconds := Tracks[10].Value;
  Result.ShutterSeconds := Tracks[11].Value;
  Result.ExitSeconds := Tracks[12].Value;
  Result.BackgroundBlur := Tracks[13].Value;
  Result.BackgroundDark := Tracks[14].Value;
  ResolvePhotoShotTiming(Result, Rate, Scale);
end;

end.
