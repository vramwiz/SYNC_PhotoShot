unit SYNC_PhotoShot_MP3;

// MP3 を音声再生用の44100Hz stereo floatへ変換する。
// ファイル・借用ストリーム・RCDATAを共通デコーダーへ渡す。外部コマンド・一時ファイル不要。
interface
uses System.SysUtils, System.Classes, Winapi.Windows;

type
  TPhotoShotPCM = record
    SampleRate, Channels: Integer;
    Samples: TArray<Single>;
    function FrameCount: Integer;
  end;

// 呼出側所有の管理配列を返す。Cancel=True は EAbort、失敗は例外。
// コールバック中ではなく初期化時に呼ぶ。
function DecodePhotoShotMP3(const FileName: string;
  const Cancel: TFunc<Boolean> = nil): TPhotoShotPCM;
// Streamは借用。先頭から読み取り、位置を変更するが解放しない。
function DecodePhotoShotMP3Stream(Stream: TStream;
  const Cancel: TFunc<Boolean> = nil): TPhotoShotPCM;
// ModuleのRCDATAを直接デコードする。リソース欠落・不正MP3は例外。
function DecodePhotoShotMP3Resource(Module: HMODULE; const ResourceName: string;
  const Cancel: TFunc<Boolean> = nil): TPhotoShotPCM;

implementation
uses MP3Decoder;

function TPhotoShotPCM.FrameCount: Integer;
begin
  if Channels > 0 then Result := Length(Samples) div Channels else Result := 0;
end;

function ConvertPCM(const Audio: TDecodedAudio;
  const Cancel: TFunc<Boolean>): TPhotoShotPCM;
var
  PCM: TBytes;
  I, Count: Integer;
  Sample: SmallInt;
begin
  Result := Default(TPhotoShotPCM);
  PCM := ToStereo44100(Audio, Cancel);
  if (Length(PCM)=0) or (Length(PCM) mod 4<>0) then
    raise EMP3DecodeError.Create('Invalid stereo PCM output');
  Result.SampleRate:=44100;
  Result.Channels:=2;
  Count:=Length(PCM) div 2;
  SetLength(Result.Samples,Count);
  for I:=0 to Count-1 do
  begin
    if (I and $FFF=0) and Assigned(Cancel) and Cancel() then Abort;
    Move(PCM[I*2],Sample,SizeOf(Sample));
    Result.Samples[I]:=Sample/32768.0;
  end;
end;

function DecodePhotoShotMP3(const FileName: string;
  const Cancel: TFunc<Boolean>): TPhotoShotPCM;
begin
  Result:=ConvertPCM(DecodeMP3(FileName,Cancel),Cancel);
end;

function DecodePhotoShotMP3Stream(Stream: TStream;
  const Cancel: TFunc<Boolean>): TPhotoShotPCM;
begin
  Result:=ConvertPCM(DecodeMP3Stream(Stream,Cancel),Cancel);
end;

function DecodePhotoShotMP3Resource(Module: HMODULE; const ResourceName: string;
  const Cancel: TFunc<Boolean>): TPhotoShotPCM;
var Stream: TResourceStream;
begin
  Stream:=TResourceStream.Create(Module,ResourceName,RT_RCDATA);
  try
    Result:=DecodePhotoShotMP3Stream(Stream,Cancel);
  finally
    Stream.Free;
  end;
end;

end.
