program PhotoShotAudioMixTests;

{$APPTYPE CONSOLE}
{$RANGECHECKS ON}
{$OVERFLOWCHECKS ON}

uses
  System.SysUtils, System.Math,
  SYNC_PhotoShot_AudioMix in '..\Source\Common\SYNC_PhotoShot_AudioMix.pas';

var
  Checks: Integer;

procedure Check(Value: Boolean; const Msg: string);
begin
  Inc(Checks);
  if not Value then raise Exception.Create(Msg);
end;

procedure Near(A, B: Double; const Msg: string);
begin
  Check(Abs(A - B) < 0.000001, Msg);
end;

procedure TimestampTests;
begin
  Check(PhotoShotShutterSample(15, 30, 30, 1, 44100) = 66150, '30fps');
  Check(PhotoShotShutterSample(15, 30, 30, 1, 48000) = 72000, '48k timestamp');
  Check(PhotoShotShutterSample(10, 20, 30000, 1001, 48000) = 48048, 'NTSC');
  Check(PhotoShotShutterSample(1, 0, 24, 1, 44100) = 1838, 'sample rounding');
  Check(PhotoShotShutterSample(-5, 30, 30, 1, 44100) = 44100, 'negative frames');
  Check(PhotoShotShutterSample(15, 30, 0, 1, 44100) = 0, 'invalid rate');
  Check(PhotoShotShutterSample(15, 30, 30, 0, 44100) = 0, 'invalid scale');
  Check(PhotoShotShutterSample(15, 30, 30, 1, 0) = 0, 'invalid sample rate');
  Check(PhotoShotShutterSample(High(Integer), High(Integer), 1,
    High(Integer), High(Integer)) = High(Int64), 'saturating timestamp');
end;

procedure BasicMixTests;
var
  PCM, B: TArray<Single>;
  I: Integer;
begin
  PCM := TArray<Single>.Create(0.5, -0.5, 0.25, -0.25, 0.75, -0.75, 0.9);
  B := TArray<Single>.Create(0.1, 0.1, 0.1, 0.1, 0.1);
  MixPhotoShotChannel(B, PCM, 0, 99, 100, 100);
  Near(B[0], 0.1, 'pre-shutter unchanged');
  Near(B[1], 0.6, 'left source begins');
  Near(B[2], 0.35, 'left source second');
  Near(B[3], 0.85, 'left tail');
  Near(B[4], 0.1, 'odd trailing sample ignored');
  B := TArray<Single>.Create(0.1, 0.1, 0.1, 0.1);
  MixPhotoShotChannel(B, PCM, 1, 100, 100, 50);
  Near(B[0], -0.15, 'right volume half');
  Near(B[1], -0.025, 'right second');
  Near(B[2], -0.275, 'right tail');
  Near(B[3], 0.1, 'post-source unchanged');
  B := TArray<Single>.Create(0.1, 0.1, 0.1);
  MixPhotoShotChannel(B, PCM, 0, 100, 100, 0);
  MixPhotoShotChannel(B, PCM, 0, 100, 100, -100);
  MixPhotoShotChannel(B, PCM, 2, 100, 100, 100);
  for I := 0 to High(B) do Near(B[I], 0.1, 'muted or invalid channel');
  B := TArray<Single>.Create(0, 0, 0);
  MixPhotoShotChannel(B, PCM, 0, 100, 100, 200);
  Near(B[0], 0.5, 'volume capped at 100');
  PCM := TArray<Single>.Create(0.8, -0.8);
  B := TArray<Single>.Create(0.8);
  MixPhotoShotChannel(B, PCM, 0, 0, 0, 100);
  Near(B[0], 1, 'positive clip');
  B := TArray<Single>.Create(-0.8);
  MixPhotoShotChannel(B, PCM, 1, 0, 0, 100);
  Near(B[0], -1, 'negative clip');
  B := TArray<Single>.Create(0.1, 0.1);
  MixPhotoShotChannel(B, PCM, 0, High(Int64), Low(Int64), 100);
  Near(B[0], 0.1, 'extreme difference avoids overflow');
  MixPhotoShotChannel(B, PCM, 0, High(Int64), High(Int64), 100);
  Near(B[0], 0.9, 'extreme start first sample');
  Near(B[1], 0.1, 'extreme start overflows are skipped');
end;

procedure ResampleAndOrderTests(SourceRate, OutputRate: Integer);
const
  SourceFrames = 4410;
  Total = 6000;
  Capture = 317;
var
  PCM, Whole, Block, Reassembled: TArray<Single>;
  I, J, Start, N, Ch, Pass, BlockIndex: Integer;
begin
  SetLength(PCM, SourceFrames * 2);
  for I := 0 to SourceFrames - 1 do
  begin
    PCM[I * 2] := Sin(I * 0.01) * 0.3;
    PCM[I * 2 + 1] := Cos(I * 0.017) * 0.2;
  end;
  for Ch := 0 to 1 do
  begin
    SetLength(Whole, Total);
    for I := 0 to Total - 1 do Whole[I] := 0.05;
    MixPhotoShotChannel(Whole, PCM, Ch, 0, Capture, 75, SourceRate, OutputRate);
    for Pass := 0 to 1 do
    begin
      SetLength(Reassembled, Total);
      // 24 ブロックを逆順または 5 刻みの置換順で処理する。
      for J := 0 to 23 do
      begin
        if Pass = 0 then BlockIndex := 23 - J
        else BlockIndex := (J * 5) mod 24;
        Start := BlockIndex * 250;
        N := Min(250, Total - Start);
        SetLength(Block, N);
        for I := 0 to N - 1 do Block[I] := 0.05;
        MixPhotoShotChannel(Block, PCM, Ch, Start, Capture, 75,
          SourceRate, OutputRate);
        for I := 0 to N - 1 do Reassembled[Start + I] := Block[I];
      end;
      for I := 0 to Total - 1 do
        Check(Whole[I] = Reassembled[I], 'block-independent exact sample');
    end;
    for I := 0 to Capture - 1 do Near(Whole[I], 0.05, 'pre-capture sample');
    // 音源末尾の直前まで再生し、映像演出長などで切られていないことを検査する。
    I := Capture + Floor((SourceFrames - 2) * Double(OutputRate) / SourceRate);
    Check(Abs(Whole[I] - 0.05) > 0.001, 'audio tail remains');
    I := Capture + Ceil(SourceFrames * Double(OutputRate) / SourceRate);
    Near(Whole[I], 0.05, 'after source duration unchanged');
  end;
end;

procedure LinearInterpolationTest;
var
  PCM, B: TArray<Single>;
begin
  PCM := TArray<Single>.Create(0, 0, 1, 1);
  B := TArray<Single>.Create(0, 0, 0, 0, 0);
  MixPhotoShotChannel(B, PCM, 0, 0, 0, 100, 2, 4);
  Near(B[0], 0, 'interpolation begin');
  Near(B[1], 0.5, 'interpolation midpoint');
  Near(B[2], 1, 'interpolation exact source');
  Near(B[3], 1, 'final sample extension');
  Near(B[4], 0, 'resampled clip end');
end;

begin
  try
    TimestampTests;
    BasicMixTests;
    LinearInterpolationTest;
    ResampleAndOrderTests(44100, 44100);
    ResampleAndOrderTests(44100, 48000);
    ResampleAndOrderTests(48000, 44100);
    Writeln('PASS: ', Checks, ' audio assertions; timestamps, volume, clipping,');
    Writeln('linear resampling, absolute block order, tail and overflow.');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
