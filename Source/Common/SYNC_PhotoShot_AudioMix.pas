unit SYNC_PhotoShot_AudioMix;

// シャッターの絶対サンプル位置を基準に、デコード済み PCM を既存音声へ加算する。
// 再生カーソルや演出段階に依存せず、音の末尾まで任意順のブロックを処理する。

interface

// Buffer は単一チャンネルの既存音声。StereoPCM は LR 交互、Channel は 0=L / 1=R。
// BlockSampleStart と ShutterSample はオブジェクト先頭からのサンプル位置。
// Volume は 0..100（範囲外は制限）。入力 PCM の所有権を移さず、Buffer だけを更新。
// 開始位置は出力レート単位。異なる音源レートは絶対時刻から線形補間する。
// 奇数個の PCM の末尾は無視。無効チャンネル、音量 0、範囲外は既存音を変更しない。
procedure MixPhotoShotChannel(var Buffer: TArray<Single>;
  const StereoPCM: TArray<Single>; Channel: Integer;
  BlockSampleStart, ShutterSample: Int64; Volume: Double;
  SourceRate: Integer = 44100; OutputRate: Integer = 44100);

// fps=Rate/Scale として登場＋待機フレームをサンプル位置へ丸める。
// 不正なレートは 0、負のフレーム数は 0、Int64 を越える値は上限へ制限する。
function PhotoShotShutterSample(EnterFrames, WaitFrames, Rate, Scale,
  SampleRate: Integer): Int64;

implementation

uses
  System.Math;

function PhotoShotShutterSample(EnterFrames, WaitFrames, Rate, Scale,
  SampleRate: Integer): Int64;
var
  Frames: Int64;
  Position: Double;
begin
  Result := 0;
  if (Rate <= 0) or (Scale <= 0) or (SampleRate <= 0) then Exit;
  Frames := Int64(Max(0, EnterFrames)) + Max(0, WaitFrames);
  Position := Frames * (Double(Scale) / Rate) * SampleRate;
  // Double(High(Int64)) は 2^63 に丸められるため、Round の前に境界を検査する。
  if Position >= Double(High(Int64)) then Exit(High(Int64));
  Result := Round(Position);
end;

procedure MixPhotoShotChannel(var Buffer: TArray<Single>;
  const StereoPCM: TArray<Single>; Channel: Integer;
  BlockSampleStart, ShutterSample: Int64; Volume: Double;
  SourceRate, OutputRate: Integer);
var
  I: NativeInt;
  Sample, Relative, FrameCount, SourceIndex, NextIndex: Int64;
  Gain, Value, SourceValue, Position, Fraction, NextValue: Double;
begin
  if (Channel < 0) or (Channel > 1) or (Length(Buffer) = 0) or
    (Length(StereoPCM) < 2) or (SourceRate <= 0) or (OutputRate <= 0) or
    IsNan(Volume) then Exit;
  Gain := EnsureRange(Volume, 0.0, 100.0) / 100;
  if Gain = 0 then Exit;
  FrameCount := Length(StereoPCM) div 2;
  for I := 0 to Length(Buffer) - 1 do
  begin
    if BlockSampleStart > High(Int64) - I then Break;
    Sample := BlockSampleStart + I;
    if Sample < ShutterSample then Continue;
    // 正負をまたぐ差が Int64 を越える場合は音源の長さも必ず越えている。
    if (ShutterSample < 0) and (Sample > High(Int64) + ShutterSample) then Break;
    Relative := Sample - ShutterSample;
    Position := Relative * (Double(SourceRate) / OutputRate);
    if Position >= FrameCount then Break;
    SourceIndex := Floor(Position);
    NextIndex := Min(SourceIndex + 1, FrameCount - 1);
    Fraction := Position - SourceIndex;
    SourceValue := StereoPCM[NativeInt(SourceIndex) * 2 + Channel];
    NextValue := StereoPCM[NativeInt(NextIndex) * 2 + Channel];
    if IsNan(SourceValue) or IsInfinite(SourceValue) or
      IsNan(NextValue) or IsInfinite(NextValue) then Continue;
    SourceValue := SourceValue + (NextValue - SourceValue) * Fraction;
    Value := Buffer[I] + SourceValue * Gain;
    Buffer[I] := EnsureRange(Value, -1.0, 1.0);
  end;
end;

end.
