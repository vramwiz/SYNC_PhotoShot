unit SYNC_PhotoShot_ShutterSound;

// カメラの打音、短い共鳴、モーターの振動をサイン波と固定シードのノイズで合成する。
interface

const
  PhotoShotShutterSampleRate = 48000;

type
  // 順番は「カメラ種類」の選択肢と一致する。
  TPhotoShotShutterKind = (skSmartphone, skCompact, skDSLR, skInstant);

// 指定カメラの PCM を LR 交互の配列として返す。左右には同じ波形を入れる。
// 生成は決定的で、プラグインの初期化時に一度行う。
function SynthesizePhotoShotShutter(Kind: TPhotoShotShutterKind): TArray<Single>;

implementation

uses
  System.Math;

const
  TwoPi = 2 * Pi;

type
  TSamples = TArray<Single>;

function NextNoise(var State: UInt32): Double;
begin
  State := State xor (State shl 13);
  State := State xor (State shr 17);
  State := State xor (State shl 5);
  Result := State * (2.0 / 4294967296.0) - 1.0;
end;

procedure AddStrike(var Samples: TSamples; Offset, Strength, Frequency,
  SnapDecay, BodyDecay, Brightness: Double; var State: UInt32);
var
  Start, Limit, I: Integer;
  T, White, BandLow, BodyLow, Edge, Snap, Resonance, Attack: Double;
begin
  Start := Round(Offset * PhotoShotShutterSampleRate);
  Limit := Min(High(Samples), Start + Ceil(8 * Max(SnapDecay, BodyDecay) * PhotoShotShutterSampleRate));
  BandLow := 0;
  BodyLow := 0;
  for I := Start to Limit do
  begin
    T := (I - Start) / PhotoShotShutterSampleRate;
    White := NextNoise(State);
    BandLow := BandLow + 0.32 * (White - BandLow);
    BodyLow := BodyLow + 0.04 * (White - BodyLow);
    Edge := (BandLow - BodyLow) + Brightness * (White - BandLow);
    Snap := (0.78 * Edge + 0.18 * Sin(TwoPi * Frequency * 3.7 * T)) *
      Exp(-T / SnapDecay);
    Resonance := (0.58 * Sin(TwoPi * Frequency * T) +
      0.26 * Sin(TwoPi * Frequency * 2.23 * T) +
      0.13 * Sin(TwoPi * Frequency * 3.11 * T)) * Exp(-T / BodyDecay);
    Attack := 1 - Exp(-T / 0.00018);
    Samples[I] := Samples[I] + Strength * Attack * (Snap + Resonance);
  end;
end;

procedure AddMotor(var Samples: TSamples; Offset, Duration, Strength,
  StartFrequency, EndFrequency: Double; var State: UInt32);
var
  Start, Limit, I: Integer;
  T, Progress, Phase, Frequency, NoiseBand, Envelope, Rattle: Double;
begin
  Start := Round(Offset * PhotoShotShutterSampleRate);
  Limit := Min(High(Samples), Start + Floor(Duration * PhotoShotShutterSampleRate));
  NoiseBand := 0;
  Phase := 0;
  for I := Start to Limit do
  begin
    T := (I - Start) / PhotoShotShutterSampleRate;
    Progress := T / Duration;
    Frequency := StartFrequency + (EndFrequency - StartFrequency) *
      (1 - Exp(-7 * Progress));
    Phase := Phase + TwoPi * Frequency / PhotoShotShutterSampleRate;
    NoiseBand := NoiseBand + 0.23 * (NextNoise(State) - NoiseBand);
    Envelope := Min(1.0, T / 0.023) * Min(1.0, (Duration - T) / 0.032);
    Rattle := 0.72 + 0.28 * Cos(TwoPi * 31 * T);
    Samples[I] := Samples[I] + Strength * Envelope * Rattle *
      (0.45 * Sin(Phase) + 0.28 * Sin(2 * Phase) +
       0.14 * Sin(5 * Phase) + 0.30 * NoiseBand);
  end;
end;

procedure ScalePeakAndFade(var Samples: TSamples; TargetPeak: Double);
const
  FadeFrames = PhotoShotShutterSampleRate div 250;
var
  I: Integer;
  Gain, Peak: Double;
begin
  for I := 0 to FadeFrames - 1 do
    Samples[High(Samples) - I] := Samples[High(Samples) - I] *
      (I / FadeFrames);
  Peak := 0;
  for I := 0 to High(Samples) do
    Peak := Max(Peak, Abs(Samples[I]));
  if Peak = 0 then
    Exit;
  Gain := TargetPeak / Peak;
  for I := 0 to High(Samples) do
    Samples[I] := Samples[I] * Gain;
end;

function SynthesizeMonoShutter(Kind: TPhotoShotShutterKind): TSamples;
const
  Duration: array[TPhotoShotShutterKind] of Double = (0.132, 0.218, 0.258, 0.654);
  Peak: array[TPhotoShotShutterKind] of Double = (0.47, 0.55, 0.68, 0.59);
var
  NoiseState: UInt32;
begin
  SetLength(Result, Round(Duration[Kind] * PhotoShotShutterSampleRate));
  NoiseState := $13579BDF + UInt32(Ord(Kind)) * $13579;
  case Kind of
    skSmartphone:
    begin
      AddStrike(Result, 0.002, 0.85, 1620, 0.0020, 0.0055, 0.85, NoiseState);
      AddStrike(Result, 0.029, 0.35, 2180, 0.0014, 0.0043, 0.92, NoiseState);
      AddStrike(Result, 0.052, 0.12, 1120, 0.0015, 0.0040, 0.53, NoiseState);
    end;
    skCompact:
    begin
      AddStrike(Result, 0.003, 0.78, 890, 0.0028, 0.0075, 0.73, NoiseState);
      AddMotor(Result, 0.018, 0.067, 0.12, 465, 730, NoiseState);
      AddStrike(Result, 0.079, 0.57, 1330, 0.0022, 0.0068, 0.81, NoiseState);
      AddStrike(Result, 0.108, 0.16, 790, 0.0014, 0.0060, 0.54, NoiseState);
    end;
    skDSLR:
    begin
      AddStrike(Result, 0.002, 1.03, 240, 0.0048, 0.0145, 0.49, NoiseState);
      AddStrike(Result, 0.017, 0.57, 1270, 0.0025, 0.0072, 0.92, NoiseState);
      AddStrike(Result, 0.061, 0.51, 970, 0.0026, 0.0085, 0.78, NoiseState);
      AddStrike(Result, 0.099, 0.83, 316, 0.0042, 0.0150, 0.52, NoiseState);
      AddStrike(Result, 0.125, 0.22, 690, 0.0025, 0.0080, 0.68, NoiseState);
    end;
    skInstant:
    begin
      AddStrike(Result, 0.003, 0.95, 510, 0.0039, 0.0130, 0.60, NoiseState);
      AddStrike(Result, 0.068, 0.54, 920, 0.0040, 0.0100, 0.77, NoiseState);
      AddMotor(Result, 0.103, 0.458, 0.30, 160, 248, NoiseState);
      AddStrike(Result, 0.344, 0.16, 410, 0.0052, 0.0098, 0.46, NoiseState);
      AddStrike(Result, 0.552, 0.36, 315, 0.0044, 0.0120, 0.58, NoiseState);
    end;
  end;
  ScalePeakAndFade(Result, Peak[Kind]);
end;

function SynthesizePhotoShotShutter(Kind: TPhotoShotShutterKind): TArray<Single>;
var
  Mono: TSamples;
  I: Integer;
begin
  Mono := SynthesizeMonoShutter(Kind);
  SetLength(Result, Length(Mono) * 2);
  for I := 0 to High(Mono) do
  begin
    Result[I * 2] := Mono[I];
    Result[I * 2 + 1] := Mono[I];
  end;
end;

end.
