unit SYNC_PhotoShot_Timeline;

// 演出段階と相対アニメーションをフレーム番号から純粋計算する。
// 再生履歴や共有可変状態を持たず、ホストの現在のパラメータを常に基準にする。

interface

type
  TPhotoShotSettings = record
    CameraKind, Orientation, ShutterEffect: Integer;
    CameraEnter, CameraExit, PreviewEnter, PreviewStyle: Integer;
    X, Y, Scale, Rotation, Opacity: Double;
    InnerX, InnerY, InnerZoom, InnerBlur: Double;
    PreviewX, PreviewY, PreviewScale, PreviewRotation: Double;
    BackgroundBlur, BackgroundDark: Double;
    EnterFrames, WaitFrames, ShutterFrames, ExitFrames, PreviewFrames,
      HoldFrames: Integer;
  end;

  TPhotoShotState = record
    // 0=登場、1=待機、2=シャッター、3=退場、4=写真登場、5=写真保持。
    Phase: Integer;
    Progress: Double;
    ShutterFrame: Integer;
    CameraVisible, PreviewVisible: Boolean;
    // Scale は百分率、Opacity は可視率 0..100。位置は画面中心からのオフセット。
    CameraX, CameraY, CameraScale, CameraRotation, CameraOpacity: Double;
    PreviewX, PreviewY, PreviewScale, PreviewRotation, PreviewOpacity: Double;
  end;

// 30 fps を目安とした最初の演出設定を返す。時間単位はフレームで fps に依存しない。
// 戻り値は値型であり、保持する資源や副作用はない。
function DefaultPhotoShotSettings: TPhotoShotSettings;

// Frame はオブジェクト先頭からのフレーム番号。負の値は先頭へ丸める。
// ゼロ長段階は省略し、総時間を越えた場合は最後の写真を保持する。
// CameraEnter / CameraExit / PreviewEnter:
// 0=なし、1=フェード、2=ズーム、3=スライド、4=回転、5=ポップ、6=バウンド。
// 外部状態の変更、画像取得、音声再生は行わない。
function EvaluatePhotoShot(const S: TPhotoShotSettings;
  Frame, CanvasWidth, CanvasHeight: Integer): TPhotoShotState;

implementation

uses
  System.Math;

function DefaultPhotoShotSettings: TPhotoShotSettings;
begin
  Result := Default(TPhotoShotSettings);
  Result.Scale := 100;
  Result.Opacity := 100;
  Result.InnerZoom := 100;
  Result.PreviewScale := 100;
  Result.ShutterEffect := 1;
  Result.CameraEnter := 3;
  Result.CameraExit := 1;
  Result.PreviewEnter := 2;
  Result.PreviewStyle := 1;
  Result.EnterFrames := 15;
  Result.WaitFrames := 30;
  Result.ShutterFrames := 8;
  Result.ExitFrames := 12;
  Result.PreviewFrames := 15;
  Result.HoldFrames := 30;
end;

function StageProgress(LocalFrame: Int64; Duration: Integer): Double;
begin
  // 1 フレームの段階は最終値だけを表示。通常は段階末尾で確実に 1 へ到達する。
  if Duration <= 1 then Exit(1);
  Result := EnsureRange(LocalFrame / (Duration - 1), 0.0, 1.0);
end;

function EaseOut(T: Double): Double;
begin
  Result := 1 - Power(1 - T, 3);
end;

procedure ApplyEntrance(Kind: Integer; Progress: Double;
  CanvasWidth, CanvasHeight: Integer; var X, Y, Scale, Rotation, Opacity: Double);
var
  T, Weight, Overshoot, Travel: Double;
begin
  T := EnsureRange(Progress, 0.0, 1.0);
  if (Kind = 0) or (T >= 1) then Exit;
  Weight := 1 - EaseOut(T);
  // 向きやカメラ種類に依存せず、初期状態の本体を映像の左外へ退避できる距離。
  Travel := Abs(X) + Max(1, CanvasWidth) / 2 +
    Max(Max(1, CanvasWidth), Max(1, CanvasHeight)) * Max(1.0, Abs(Scale) / 100);
  case Kind of
    1: Opacity := Opacity * (1 - Weight);
    2:
      begin
        Scale := Scale * (0.12 + 0.88 * (1 - Weight));
        Opacity := Opacity * (1 - Weight);
      end;
    3: X := X - Travel * Weight;
    4:
      begin
        Rotation := Rotation - 90 * Weight;
        Scale := Scale * (0.5 + 0.5 * (1 - Weight));
        Opacity := Opacity * (1 - Weight);
      end;
    5:
      begin
        // back-out は終端で 1 に戻る。境界を明示して浮動小数誤差も残さない。
        Overshoot := 1 + 2.70158 * Power(T - 1, 3) + 1.70158 * Sqr(T - 1);
        Scale := Scale * Max(0.0, Overshoot);
        Opacity := Opacity * Min(1.0, T * 5);
      end;
    6:
      begin
        // 位置だけを変える減衰振動。終端でオフセットが厳密に 0 となる。
        Y := Y + Max(1, CanvasHeight) * 0.35 *
          Cos(T * 2.5 * Pi) * Sqr(1 - T);
        Opacity := Opacity * Min(1.0, T * 5);
      end;
  end;
end;

function EvaluatePhotoShot(const S: TPhotoShotSettings;
  Frame, CanvasWidth, CanvasHeight: Integer): TPhotoShotState;
var
  Durations: array[0..5] of Integer;
  I: Integer;
  Start, AtFrame, Capture: Int64;
begin
  Result := Default(TPhotoShotState);
  Result.CameraX := S.X;
  Result.CameraY := S.Y;
  Result.CameraScale := Max(0.0, S.Scale);
  Result.CameraRotation := S.Rotation;
  Result.CameraOpacity := EnsureRange(S.Opacity, 0.0, 100.0);
  Result.PreviewX := S.PreviewX;
  Result.PreviewY := S.PreviewY;
  Result.PreviewScale := Max(0.0, S.PreviewScale);
  Result.PreviewRotation := S.PreviewRotation;
  Result.PreviewOpacity := 100;
  Durations[0] := Max(0, S.EnterFrames);
  Durations[1] := Max(0, S.WaitFrames);
  Durations[2] := Max(0, S.ShutterFrames);
  Durations[3] := Max(0, S.ExitFrames);
  Durations[4] := Max(0, S.PreviewFrames);
  Durations[5] := Max(0, S.HoldFrames);
  Capture := Int64(Durations[0]) + Durations[1];
  if Capture > High(Integer) then Result.ShutterFrame := High(Integer)
  else Result.ShutterFrame := Integer(Capture);
  AtFrame := Max(0, Frame);
  Start := 0;
  Result.Phase := 5;
  Result.Progress := 1;
  for I := 0 to High(Durations) do
  begin
    if (Durations[I] > 0) and (AtFrame < Start + Durations[I]) then
    begin
      Result.Phase := I;
      Result.Progress := StageProgress(AtFrame - Start, Durations[I]);
      Break;
    end;
    Inc(Start, Durations[I]);
  end;
  Result.CameraVisible := Result.Phase <= 3;
  Result.PreviewVisible := Result.Phase >= 4;
  case Result.Phase of
    0: ApplyEntrance(S.CameraEnter, Result.Progress, CanvasWidth, CanvasHeight,
         Result.CameraX, Result.CameraY, Result.CameraScale,
         Result.CameraRotation, Result.CameraOpacity);
    3: ApplyEntrance(S.CameraExit, 1 - Result.Progress, CanvasWidth, CanvasHeight,
         Result.CameraX, Result.CameraY, Result.CameraScale,
         Result.CameraRotation, Result.CameraOpacity);
    4: ApplyEntrance(S.PreviewEnter, Result.Progress, CanvasWidth, CanvasHeight,
         Result.PreviewX, Result.PreviewY, Result.PreviewScale,
         Result.PreviewRotation, Result.PreviewOpacity);
  end;
end;

end.
