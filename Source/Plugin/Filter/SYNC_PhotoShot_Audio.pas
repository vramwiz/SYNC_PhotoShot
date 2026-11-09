unit SYNC_PhotoShot_Audio;

// 同梱 MP3 を初期化時にデコードし、ホストの絶対サンプル時刻から混合する。
// 映像の段階時間では余韻を切らない。コールバック中にファイル読込・デコードしない。
interface

// DLL の RCDATA に埋め込んだユーザー指定4音を優先。旧配置の Mp3 は欠落時のみ互換読込。
// 全処理はホストがコールバックを始める前に呼ぶ。終了時はホストの処理停止後に解放する。
procedure InitializePhotoShotAudio;
procedure ReleasePhotoShotAudio;
procedure RegisterPhotoShotAudioParameter(IncludeGroup: Boolean = True);
// Audio は SDK FILTER_PROC_AUDIO。入力は借用し、合成対象サンプルだけホストへ書き戻す。
function PhotoShotProcAudio(Audio: Pointer): Byte; cdecl;

implementation

// IDE が主 .res を再生成しても音源が消えないよう、ユニット専用リソースをリンク。
{$R SYNC_PhotoShot_Audio.res}

uses
  System.SysUtils, System.Math, Winapi.Windows, AviUtl2FilterTypes,
  PluginFilterTable, SYNC_PhotoShot_MP3, SYNC_PhotoShot_AudioMix,
  SYNC_PhotoShot_Parameters, SYNC_PhotoShot_Timeline;

type
  // SDK v2.1.15 filter2.h の先頭4フィールドのみ使用。
  // 新SDK末尾の audiobuffer API には依存せず、未検証のオフセットを参照しない。
  PPhotoShotAudioProc = ^TPhotoShotAudioProc;
  TPhotoShotAudioProc = record
    Scene: PSCENE_INFO;
    Object_: POBJECT_INFO;
    GetSampleData: procedure(Buffer: PSingle; Channel: Integer); cdecl;
    SetSampleData: procedure(Buffer: PSingle; Channel: Integer); cdecl;
  end;

var
  Sounds: array[0..3] of TPhotoShotPCM;
  VolumeItem: TFILTER_ITEM_TRACK;
  AudioGroup: TFILTER_ITEM_GROUP;

procedure InitializePhotoShotAudio;
const
  Names: array[0..3] of string = ('スマホ.mp3','コンデジ.mp3','一眼レフ.mp3','インスタントカメラ.mp3');
  ResourceNames: array[0..3] of string = ('PHOTOSHOT_SMARTPHONE','PHOTOSHOT_COMPACT','PHOTOSHOT_DSLR','PHOTOSHOT_INSTANT');
var
  Buffer: array[0..32767] of WideChar;
  Base: string;
  I: Integer;
begin
  GetModuleFileName(HInstance, Buffer, Length(Buffer));
  Base := ExtractFilePath(string(Buffer)) + 'Mp3\';
  for I := 0 to 3 do
  begin
    Sounds[I] := Default(TPhotoShotPCM);
    try
      if FindResource(HInstance, PChar(ResourceNames[I]), RT_RCDATA) <> 0 then
        Sounds[I] := DecodePhotoShotMP3Resource(HInstance, ResourceNames[I])
      else
        Sounds[I] := DecodePhotoShotMP3(Base + Names[I]);
    except
      on E: Exception do
        OutputDebugString(PChar('SYNC_PhotoShot MP3: ' + E.Message));
    end;
  end;
end;

procedure ReleasePhotoShotAudio;
var I: Integer;
begin
  for I := 0 to 3 do Sounds[I] := Default(TPhotoShotPCM);
end;

procedure RegisterPhotoShotAudioParameter(IncludeGroup: Boolean);
begin
  if IncludeGroup then AddGroup(AudioGroup, '音声設定', 1);
  AddTrack(VolumeItem, 'シャッター音量', 100, 0, 100, 1);
end;

function PhotoShotProcAudio(Audio: Pointer): Byte; cdecl;
var
  A: PPhotoShotAudioProc;
  S: TPhotoShotSettings;
  Kind, Channel, N, TargetRate: Integer;
  StartSample, TailSample: Int64;
  Samples: TArray<Single>;
begin
  Result := 1;
  try
    A := PPhotoShotAudioProc(Audio);
    if (A = nil) or (A^.Scene = nil) or (A^.Object_ = nil) or
      not Assigned(A^.GetSampleData) or not Assigned(A^.SetSampleData) then Exit;
    if VolumeItem.Value <= 0 then Exit;
    S := ReadPhotoShotParameters(A^.Scene^.Rate, A^.Scene^.Scale);
    Kind := EnsureRange(S.CameraKind, 0, 3);
    if Length(Sounds[Kind].Samples) = 0 then Exit;
    N := A^.Object_^.SampleNum;
    TargetRate := A^.Scene^.SampleRate;
    if (N <= 0) or (N > 1048576) or (TargetRate <= 0) then Exit;
    StartSample := PhotoShotShutterSample(S.EnterFrames,S.WaitFrames,
      A^.Scene^.Rate,A^.Scene^.Scale,TargetRate);
    TailSample := StartSample + Ceil(Sounds[Kind].FrameCount *
      (Double(TargetRate) / Sounds[Kind].SampleRate));
    if (A^.Object_^.SampleIndex >= TailSample) or
      (A^.Object_^.SampleIndex + N <= StartSample) then Exit;
    SetLength(Samples,N);
    for Channel := 0 to Min(1,A^.Object_^.ChannelNum-1) do
    begin
      A^.GetSampleData(@Samples[0],Channel);
      MixPhotoShotChannel(Samples,Sounds[Kind].Samples,Channel,
        A^.Object_^.SampleIndex,StartSample,VolumeItem.Value,
        Sounds[Kind].SampleRate,TargetRate);
      A^.SetSampleData(@Samples[0],Channel);
    end;
  except
    on E: Exception do OutputDebugString(PChar('SYNC_PhotoShot audio: '+E.Message));
  end;
end;

end.
