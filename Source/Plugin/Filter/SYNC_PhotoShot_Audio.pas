unit SYNC_PhotoShot_Audio;

// 初期化時に4種類のシャッター音を合成し、ホストの絶対サンプル時刻を基準に混合する。
// 音声コールバックは初期化済みの PCM を参照し、余韻まで既存音声に加算する。
interface

// 生成した4種類の PCM はプラグインが所有し、終了時に解放する。
// 全処理はホストがコールバックを始める前に呼ぶ。終了時はホストの処理停止後に解放する。
procedure InitializePhotoShotAudio;
procedure ReleasePhotoShotAudio;
procedure RegisterPhotoShotAudioParameter(IncludeGroup: Boolean = True);
// Audio は SDK FILTER_PROC_AUDIO。入力は借用し、合成対象サンプルだけホストへ書き戻す。
function PhotoShotProcAudio(Audio: Pointer): Byte; cdecl;

implementation

uses
  System.SysUtils, System.Math, Winapi.Windows, AviUtl2FilterTypes,
  PluginFilterTable, SYNC_PhotoShot_ShutterSound, SYNC_PhotoShot_AudioMix,
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
  Sounds: array[TPhotoShotShutterKind] of TArray<Single>;
  VolumeItem: TFILTER_ITEM_TRACK;
  AudioGroup: TFILTER_ITEM_GROUP;

procedure InitializePhotoShotAudio;
var
  Kind: TPhotoShotShutterKind;
begin
  for Kind := Low(TPhotoShotShutterKind) to High(TPhotoShotShutterKind) do
    Sounds[Kind] := SynthesizePhotoShotShutter(Kind);
end;

procedure ReleasePhotoShotAudio;
var
  Kind: TPhotoShotShutterKind;
begin
  for Kind := Low(TPhotoShotShutterKind) to High(TPhotoShotShutterKind) do
    Sounds[Kind] := nil;
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
  Kind: TPhotoShotShutterKind;
  Channel, N, TargetRate: Integer;
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
    Kind := TPhotoShotShutterKind(EnsureRange(S.CameraKind,
      Ord(Low(TPhotoShotShutterKind)), Ord(High(TPhotoShotShutterKind))));
    if Length(Sounds[Kind]) = 0 then Exit;
    N := A^.Object_^.SampleNum;
    TargetRate := A^.Scene^.SampleRate;
    if (N <= 0) or (N > 1048576) or (TargetRate <= 0) then Exit;
    StartSample := PhotoShotShutterSample(S.EnterFrames,S.WaitFrames,
      A^.Scene^.Rate,A^.Scene^.Scale,TargetRate);
    TailSample := StartSample + Ceil((Length(Sounds[Kind]) div 2) *
      (Double(TargetRate) / PhotoShotShutterSampleRate));
    if (A^.Object_^.SampleIndex >= TailSample) or
      (A^.Object_^.SampleIndex + N <= StartSample) then Exit;
    SetLength(Samples,N);
    for Channel := 0 to Min(1,A^.Object_^.ChannelNum-1) do
    begin
      A^.GetSampleData(@Samples[0],Channel);
      MixPhotoShotChannel(Samples,Sounds[Kind],Channel,
        A^.Object_^.SampleIndex,StartSample,VolumeItem.Value,
        PhotoShotShutterSampleRate,TargetRate);
      A^.SetSampleData(@Samples[0],Channel);
    end;
  except
    on E: Exception do OutputDebugString(PChar('SYNC_PhotoShot audio: '+E.Message));
  end;
end;

end.
