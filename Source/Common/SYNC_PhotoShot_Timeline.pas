unit SYNC_PhotoShot_Timeline;

// 演出段階と相対アニメーションをフレーム番号から純粋計算する。
// 再生履歴や共有可変状態を持たず、ホストの現在のパラメータを常に基準にする。

interface

type
  TPhotoShotSettings = record
    CameraKind, Orientation, ShutterEffect: Integer;
    CameraColor: Cardinal; // 共通のスマホ筐体／カメラ枠色（ARGB）。
    CameraEnter, CameraExit: Integer;
    X, Y, Scale, Rotation, Opacity: Double;
    InnerX, InnerY, InnerZoom, InnerBlur: Double;
    BackgroundBlur, BackgroundDark: Double;
    // UI の秒値が正本。フレーム値は対象シーンの fps から累積境界で導出する。
    EnterSeconds, WaitSeconds, ShutterSeconds, ExitSeconds: Double;
    EnterFrames, WaitFrames, ShutterFrames, ExitFrames: Integer;
  end;

  TPhotoShotState = record
    // 0=登場、1=待機、2=シャッター、3=退場、4=終了。
    Phase: Integer;
    Progress: Double;
    ShutterFrame: Integer;
    CameraVisible: Boolean;
    // Scale は百分率、Opacity は可視率 0..100。位置は画面中心からのオフセット。
    CameraX, CameraY, CameraScale, CameraRotation, CameraOpacity: Double;
    // 起き上がりの縦方向圧縮率。1 が通常形状。2D の奥行き表現であり3D回転ではない。
    CameraVerticalScale: Double;
  end;

// UI 初期秒値と、30 fps で導出したフレーム値を返す。
// 戻り値は値型であり、保持する資源や副作用はない。
function DefaultPhotoShotSettings: TPhotoShotSettings;

// 秒の累積境界を Round(累積秒 * Rate / Scale) で量子化し、その差を各段階の長さへ。
// Rate/Scale は SDK のシーン fps。無効 fps は例外。秒は 0..600 に制限し、非有限値は 0。
// 正の .01 秒でも低 fps では 0 frame になり得る。音声も導出撮影 frame を基準にする。
procedure ResolvePhotoShotTiming(var S: TPhotoShotSettings; Rate, Scale: Integer);
// Frame はオブジェクト先頭からのフレーム番号。負の値は先頭へ丸める。
// ゼロ長段階は省略し、総時間を越えた場合はカメラを表示しない。
// CameraEnter / CameraExit:
// 0=なし、1=フェード、2=ズームイン、3=スライド、4=回転、5=ポップ、6=バウンド。
// 7=ズームアウト、8=起き上がり。既存の選択番号と時間規則を維持する。
// 外部状態の変更、画像取得、音声再生は行わない。
function EvaluatePhotoShot(const S: TPhotoShotSettings;
  Frame, CanvasWidth, CanvasHeight: Integer): TPhotoShotState;

implementation

uses
  System.Math, System.SysUtils;

function DefaultPhotoShotSettings: TPhotoShotSettings;
begin
  Result := Default(TPhotoShotSettings);
  Result.CameraColor := $FF303840;
  Result.Scale := 100;
  Result.Opacity := 100;
  Result.InnerZoom := 100;
  Result.ShutterEffect := 1;
  Result.CameraEnter := 3;
  Result.CameraExit := 1;
  Result.EnterSeconds := 0.50;
  Result.WaitSeconds := 1.00;
  Result.ShutterSeconds := 0.27;
  Result.ExitSeconds := 0.40;
  ResolvePhotoShotTiming(Result, 30, 1);
end;

procedure ResolvePhotoShotTiming(var S: TPhotoShotSettings; Rate, Scale: Integer);
var
  Seconds: array[0..3] of Double;
  Frames: array[0..3] of Integer;
  I: Integer;
  Total, Position: Double;
  Previous, Boundary: Int64;
begin
  if (Rate <= 0) or (Scale <= 0) then
    raise EArgumentException.Create('PhotoShot requires a positive scene frame rate');
  Seconds[0] := S.EnterSeconds; Seconds[1] := S.WaitSeconds;
  Seconds[2] := S.ShutterSeconds; Seconds[3] := S.ExitSeconds;
  Total := 0;
  Previous := 0;
  for I := 0 to High(Seconds) do
  begin
    if IsNan(Seconds[I]) or IsInfinite(Seconds[I]) then Seconds[I] := 0
    else Seconds[I] := EnsureRange(Seconds[I], 0.0, 600.0);
    Total := Total + Seconds[I];
    Position := Total * (Double(Rate) / Scale);
    // SDK の Frame は Integer。異常に大きい fps でも整数 overflow を起こさない。
    if Position >= High(Integer) then Boundary := High(Integer)
    else Boundary := Round(Position);
    Frames[I] := Integer(Boundary - Previous);
    Previous := Boundary;
  end;
  S.EnterSeconds := Seconds[0]; S.WaitSeconds := Seconds[1];
  S.ShutterSeconds := Seconds[2]; S.ExitSeconds := Seconds[3];
  S.EnterFrames := Frames[0]; S.WaitFrames := Frames[1];
  S.ShutterFrames := Frames[2]; S.ExitFrames := Frames[3];
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
  CanvasWidth, CanvasHeight: Integer; ObjectWidth, ObjectHeight: Double;
  var X, Y, Scale, Rotation, Opacity, VerticalScale: Double);
var
  T, Weight, Overshoot, Travel, StartScale: Double;
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
        if T <= 0 then Overshoot := 0
        else Overshoot := 1 + 2.70158 * Power(T - 1, 3) + 1.70158 * Sqr(T - 1);
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
    7:
      begin
        // 開始は画面中央・正面で、縦横とも画面を覆う倍率を確保する。
        // 表示サイズと現在指定値から毎フレーム計算し、中間点の値にも追従する。
        StartScale := Max(Scale * 2.5, 112 *
          Max(Max(1, CanvasWidth) / Max(1.0, ObjectWidth),
              Max(1, CanvasHeight) / Max(1.0, ObjectHeight)));
        X := X * (1 - Weight);
        Y := Y * (1 - Weight);
        Scale := Scale + (StartScale - Scale) * Weight;
        Rotation := Rotation * (1 - Weight);
      end;
    8:
      begin
        // 手前下の低い角度から画面へ向ける2D演出。奥側が見える3Dモデルではない。
        Y := Y + (Max(1, CanvasHeight) * 0.58 + Abs(Y) * 0.25) * Weight;
        X := X * (1 - 0.35 * Weight);
        Scale := Scale * (1 + 0.35 * Weight);
        Rotation := Rotation - 10 * Weight;
        VerticalScale := 1 - 0.88 * Weight;
        Opacity := Opacity * Min(1.0, T * 6);
      end;
  end;
end;

procedure AnimationSizes(const S:TPhotoShotSettings; CanvasWidth,CanvasHeight:Integer;
  out CameraWidth,CameraHeight:Double);
begin
  if S.CameraKind=0 then
  begin
    if S.Orientation=1 then begin CameraWidth:=820; CameraHeight:=420; end
    else begin CameraWidth:=420; CameraHeight:=820; end;
  end
  else
  begin
    // 非スマホは筐体ではなく全canvasのファインダー。開始倍率もこの実寸から導出。
    CameraWidth:=Max(1,CanvasWidth); CameraHeight:=Max(1,CanvasHeight);
  end;
end;
function EvaluatePhotoShot(const S: TPhotoShotSettings;
  Frame, CanvasWidth, CanvasHeight: Integer): TPhotoShotState;
var
  Durations: array[0..3] of Integer;
  I: Integer;
  Start, AtFrame, Capture: Int64;
  CameraWidth, CameraHeight: Double;
begin
  Result := Default(TPhotoShotState);
  Result.CameraX := S.X;
  Result.CameraY := S.Y;
  Result.CameraScale := Max(0.0, S.Scale);
  Result.CameraRotation := S.Rotation;
  Result.CameraOpacity := EnsureRange(S.Opacity, 0.0, 100.0);
  Result.CameraVerticalScale := 1;
  AnimationSizes(S, CanvasWidth, CanvasHeight, CameraWidth, CameraHeight);
  Durations[0] := Max(0, S.EnterFrames);
  Durations[1] := Max(0, S.WaitFrames);
  Durations[2] := Max(0, S.ShutterFrames);
  Durations[3] := Max(0, S.ExitFrames);
  Capture := Int64(Durations[0]) + Durations[1];
  if Capture > High(Integer) then Result.ShutterFrame := High(Integer)
  else Result.ShutterFrame := Integer(Capture);
  AtFrame := Max(0, Frame);
  Start := 0;
  Result.Phase := 4;
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
  case Result.Phase of
    0: ApplyEntrance(S.CameraEnter, Result.Progress, CanvasWidth, CanvasHeight, CameraWidth, CameraHeight,
         Result.CameraX, Result.CameraY, Result.CameraScale,
         Result.CameraRotation, Result.CameraOpacity, Result.CameraVerticalScale);
    3: ApplyEntrance(S.CameraExit, 1 - Result.Progress, CanvasWidth, CanvasHeight, CameraWidth, CameraHeight,
         Result.CameraX, Result.CameraY, Result.CameraScale,
         Result.CameraRotation, Result.CameraOpacity, Result.CameraVerticalScale);
  end;
end;

end.
