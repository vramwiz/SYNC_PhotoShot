unit SYNC_PhotoShot_MP3;

// RhythmShooter の純 Delphi MP3 デコーダーを PhotoShot の音声再生用に接続する。
// 外部コマンド・音声デバイス・永続キャッシュを使用しない。デコードは事前準備で行う。

interface

uses
  System.SysUtils;

type
  TPhotoShotPCM = record
    SampleRate, Channels: Integer;
    Samples: TArray<Single>; // 44100 Hz、2ch、L/R 交互、PCM16 / 32768 の float。
    function FrameCount: Integer;
  end;

// 呼出側所有の管理配列を返す。Cancel=True は EAbort、デコード失敗は例外。
// 本 API は描画・音声コールバックから呼ばず、初期化やワーカー側で使用する。
function DecodePhotoShotMP3(const FileName: string;
  const Cancel: TFunc<Boolean> = nil): TPhotoShotPCM;

implementation

uses
  MP3Decoder;

function TPhotoShotPCM.FrameCount: Integer;
begin
  if Channels > 0 then Result := Length(Samples) div Channels
  else Result := 0;
end;

function DecodePhotoShotMP3(const FileName: string;
  const Cancel: TFunc<Boolean>): TPhotoShotPCM;
var
  Audio: TDecodedAudio;
  PCM: TBytes;
  I, Count: Integer;
  Sample: SmallInt;
begin
  Result := Default(TPhotoShotPCM);
  Audio := DecodeMP3(FileName, Cancel);
  PCM := ToStereo44100(Audio, Cancel);
  Audio.PCM := nil;
  if (Length(PCM) = 0) or (Length(PCM) mod 4 <> 0) then
    raise EMP3DecodeError.Create('Invalid stereo PCM output');
  Result.SampleRate := 44100;
  Result.Channels := 2;
  Count := Length(PCM) div 2;
  SetLength(Result.Samples, Count);
  for I := 0 to Count - 1 do
  begin
    if (I and $FFF = 0) and Assigned(Cancel) and Cancel() then Abort;
    Move(PCM[I * 2], Sample, SizeOf(Sample));
    Result.Samples[I] := Sample / 32768.0;
  end;
end;

end.
