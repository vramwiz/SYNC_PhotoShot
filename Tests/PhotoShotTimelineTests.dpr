program PhotoShotTimelineTests;

{$APPTYPE CONSOLE}
{$RANGECHECKS ON}
{$OVERFLOWCHECKS ON}

// ホストや描画に依存せず、フレーム境界と純粋な演出計算を検証する。
uses
  System.SysUtils,
  SYNC_PhotoShot_Timeline in '..\Source\Common\SYNC_PhotoShot_Timeline.pas';

var
  Checks: Integer;

procedure Check(Condition: Boolean; const Message: string);
begin
  Inc(Checks);
  if not Condition then
    raise Exception.Create(Message);
end;

procedure Equal(Expected, Actual: Double; const Message: string);
begin
  Check(Expected = Actual, Message + ': expected=' + FloatToStr(Expected) +
    ', actual=' + FloatToStr(Actual));
end;

procedure SameState(const A, B: TPhotoShotState);
begin
  Check(A.Phase = B.Phase, 'stable phase');
  Equal(A.Progress, B.Progress, 'stable progress');
  Check(A.ShutterFrame = B.ShutterFrame, 'stable capture frame');
  Check(A.CameraVisible = B.CameraVisible, 'stable camera visibility');
  Check(A.PreviewVisible = B.PreviewVisible, 'stable preview visibility');
  Equal(A.CameraX, B.CameraX, 'stable camera x');
  Equal(A.CameraY, B.CameraY, 'stable camera y');
  Equal(A.CameraScale, B.CameraScale, 'stable camera scale');
  Equal(A.CameraRotation, B.CameraRotation, 'stable camera rotation');
  Equal(A.CameraOpacity, B.CameraOpacity, 'stable camera opacity');
  Equal(A.PreviewX, B.PreviewX, 'stable preview x');
  Equal(A.PreviewY, B.PreviewY, 'stable preview y');
  Equal(A.PreviewScale, B.PreviewScale, 'stable preview scale');
  Equal(A.PreviewRotation, B.PreviewRotation, 'stable preview rotation');
  Equal(A.PreviewOpacity, B.PreviewOpacity, 'stable preview opacity');
end;

procedure BoundaryTests;
const
  Starts: array[0..5] of Integer = (0, 15, 45, 53, 65, 80);
  Ends: array[0..5] of Integer = (14, 44, 52, 64, 79, 109);
var
  S: TPhotoShotSettings;
  R: TPhotoShotState;
  I: Integer;
begin
  S := DefaultPhotoShotSettings;
  for I := 0 to 5 do
  begin
    R := EvaluatePhotoShot(S, Starts[I], 1920, 1080);
    Check(R.Phase = I, 'stage start phase');
    Equal(0, R.Progress, 'stage start progress');
    Check(R.ShutterFrame = 45, 'capture frame');
    Check(R.CameraVisible = (I <= 3), 'camera stage visibility');
    Check(R.PreviewVisible = (I >= 4), 'preview stage visibility');
    R := EvaluatePhotoShot(S, Ends[I], 1920, 1080);
    Check(R.Phase = I, 'stage end phase');
    Equal(1, R.Progress, 'stage end progress');
  end;
  SameState(EvaluatePhotoShot(S, -1, 1920, 1080),
    EvaluatePhotoShot(S, 0, 1920, 1080));
  R := EvaluatePhotoShot(S, 110, 1920, 1080);
  Check((R.Phase = 5) and R.PreviewVisible and not R.CameraVisible,
    'hold beyond duration');
  Equal(1, R.Progress, 'hold complete');
  SameState(R, EvaluatePhotoShot(S, High(Integer), 1920, 1080));
end;

procedure ZeroAndOneFrameTests;
var
  S: TPhotoShotSettings;
  R: TPhotoShotState;
  I: Integer;
begin
  S := DefaultPhotoShotSettings;
  S.EnterFrames := 0;
  R := EvaluatePhotoShot(S, 0, 1920, 1080);
  Check((R.Phase = 1) and (R.ShutterFrame = 30), 'skip enter');
  S.WaitFrames := 0;
  R := EvaluatePhotoShot(S, 0, 1920, 1080);
  Check((R.Phase = 2) and (R.ShutterFrame = 0), 'skip wait');
  S.ShutterFrames := 0;
  R := EvaluatePhotoShot(S, 0, 1920, 1080);
  Check(R.Phase = 3, 'skip shutter');
  S.ExitFrames := 0;
  R := EvaluatePhotoShot(S, 0, 1920, 1080);
  Check(R.Phase = 4, 'skip exit');
  S.PreviewFrames := 0;
  R := EvaluatePhotoShot(S, 0, 1920, 1080);
  Check((R.Phase = 5) and R.PreviewVisible, 'skip preview animation');
  S.HoldFrames := 0;
  R := EvaluatePhotoShot(S, 0, 1920, 1080);
  Check((R.Phase = 5) and R.PreviewVisible and not R.CameraVisible,
    'all-zero immediate preview');
  Equal(1, R.Progress, 'all-zero progress');
  SameState(R, EvaluatePhotoShot(S, 10000, 1920, 1080));
  S.EnterFrames := -1;
  S.WaitFrames := -1;
  S.ShutterFrames := -1;
  S.ExitFrames := -1;
  S.PreviewFrames := -1;
  S.HoldFrames := -1;
  SameState(R, EvaluatePhotoShot(S, 0, 1920, 1080));

  S.EnterFrames := 1;
  S.WaitFrames := 1;
  S.ShutterFrames := 1;
  S.ExitFrames := 1;
  S.PreviewFrames := 1;
  S.HoldFrames := 1;
  for I := 0 to 5 do
  begin
    R := EvaluatePhotoShot(S, I, 1920, 1080);
    Check(R.Phase = I, 'one-frame phase');
    Equal(1, R.Progress, 'one-frame complete');
    Check(R.ShutterFrame = 2, 'one-frame shutter point');
  end;
  R := EvaluatePhotoShot(S, 6, 1920, 1080);
  Check(R.Phase = 5, 'one-frame final hold');
end;

procedure AnimationTests;
var
  S: TPhotoShotSettings;
  R: TPhotoShotState;
  Kind: Integer;
begin
  S := DefaultPhotoShotSettings;
  S.X := 123.75;
  S.Y := -42.5;
  S.Scale := 67.25;
  S.Rotation := 27.125;
  S.Opacity := 83;
  S.PreviewX := -151.5;
  S.PreviewY := 84.25;
  S.PreviewScale := 124.75;
  S.PreviewRotation := -33.5;
  for Kind := 0 to 6 do
  begin
    S.CameraEnter := Kind;
    S.CameraExit := Kind;
    S.PreviewEnter := Kind;
    R := EvaluatePhotoShot(S, 14, 1920, 1080);
    Equal(S.X, R.CameraX, 'entrance final x');
    Equal(S.Y, R.CameraY, 'entrance final y');
    Equal(S.Scale, R.CameraScale, 'entrance final scale');
    Equal(S.Rotation, R.CameraRotation, 'entrance final rotation');
    Equal(S.Opacity, R.CameraOpacity, 'entrance final opacity');
    R := EvaluatePhotoShot(S, 53, 1920, 1080);
    Equal(S.X, R.CameraX, 'exit initial x');
    Equal(S.Y, R.CameraY, 'exit initial y');
    Equal(S.Scale, R.CameraScale, 'exit initial scale');
    Equal(S.Rotation, R.CameraRotation, 'exit initial rotation');
    Equal(S.Opacity, R.CameraOpacity, 'exit initial opacity');
    R := EvaluatePhotoShot(S, 79, 1920, 1080);
    Equal(S.PreviewX, R.PreviewX, 'preview final x');
    Equal(S.PreviewY, R.PreviewY, 'preview final y');
    Equal(S.PreviewScale, R.PreviewScale, 'preview final scale');
    Equal(S.PreviewRotation, R.PreviewRotation, 'preview final rotation');
    Equal(100, R.PreviewOpacity, 'preview final opacity');
  end;
  S.CameraEnter := 0;
  R := EvaluatePhotoShot(S, 0, 1920, 1080);
  Equal(S.X, R.CameraX, 'manual x');
  Equal(S.Scale, R.CameraScale, 'manual scale');
  Equal(S.Opacity, R.CameraOpacity, 'manual opacity');
  // 中間点等で現在値が変わっても終端を前の設定に固定しない。
  S.X := -799;
  S.Scale := 241;
  R := EvaluatePhotoShot(S, 14, 1920, 1080);
  Equal(S.X, R.CameraX, 'live parameter x');
  Equal(S.Scale, R.CameraScale, 'live parameter scale');
end;

procedure DeterminismTests;
var
  S: TPhotoShotSettings;
  Baseline: array[0..511] of TPhotoShotState;
  I, J, Kind: Integer;
begin
  for Kind := 0 to 6 do
  begin
    S := DefaultPhotoShotSettings;
    S.CameraEnter := Kind;
    S.CameraExit := Kind;
    S.PreviewEnter := Kind;
    for I := 0 to 511 do
      Baseline[I] := EvaluatePhotoShot(S, I, 1920, 1080);
    for I := 511 downto 0 do
      SameState(Baseline[I], EvaluatePhotoShot(S, I, 1920, 1080));
    // 137 と 512 は互いに素で、全フレームを非連続な順序で一度ずつ再評価する。
    for I := 0 to 511 do
    begin
      J := (I * 137) mod 512;
      SameState(Baseline[J], EvaluatePhotoShot(S, J, 1920, 1080));
    end;
  end;
end;

procedure OverflowTests;
var
  S: TPhotoShotSettings;
  R: TPhotoShotState;
begin
  S := DefaultPhotoShotSettings;
  S.EnterFrames := High(Integer);
  S.WaitFrames := High(Integer);
  S.ShutterFrames := High(Integer);
  S.ExitFrames := High(Integer);
  S.PreviewFrames := High(Integer);
  S.HoldFrames := High(Integer);
  R := EvaluatePhotoShot(S, High(Integer), 1920, 1080);
  Check(R.Phase = 1, 'large duration phase');
  Check(R.ShutterFrame = High(Integer), 'capture frame saturates');
  Equal(0, R.Progress, 'large duration boundary');
  S.EnterFrames := 0;
  S.WaitFrames := 0;
  S.ShutterFrames := 0;
  S.ExitFrames := 0;
  S.PreviewFrames := 0;
  R := EvaluatePhotoShot(S, High(Integer), 1920, 1080);
  Check((R.Phase = 5) and (R.Progress = 1), 'large hold duration');
end;

begin
  try
    BoundaryTests;
    ZeroAndOneFrameTests;
    AnimationTests;
    DeterminismTests;
    OverflowTests;
    Writeln('PASS: ', Checks, ' assertions; timeline boundaries, zero/one-frame,');
    Writeln('all 7 animations, live parameters, random-access order, overflow.');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
