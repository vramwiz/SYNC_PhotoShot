program PhotoShotHostTests;

{$APPTYPE CONSOLE}
{$ALIGN 8}
{$POINTERMATH ON}
{$RANGECHECKS ON}
{$OVERFLOWCHECKS ON}

// 3 exports の通常 .auf2 を独立 EXE から読む SDK mock 統合テスト。
// 補助プラグインは作成・登録せず、実機ホストの動作を保証する試験ではない。
uses
  System.SysUtils, System.Math, Winapi.Windows,
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas';

type
  TInitialize = function(Version: Cardinal): Byte; cdecl;
  TUninitialize = procedure; cdecl;
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;
  TAudio = record
    Scene: PSCENE_INFO;
    Object_: POBJECT_INFO;
    GetSampleData: procedure(Buffer: PSingle; Channel: Integer); cdecl;
    SetSampleData: procedure(Buffer: PSingle; Channel: Integer); cdecl;
  end;
  TItemHeader = record
    ItemType, Name: PWideChar;
  end;
  PItemHeader = ^TItemHeader;

const
  W = 640;
  H = 360;
var
  Checks, Writes, AudioWrites: Integer;
  Table: PFILTER_PLUGIN_TABLE;
  Scene: TSCENE_INFO;
  Obj: TOBJECT_INFO;
  Video: TFILTER_PROC_VIDEO;
  Audio: TAudio;
  Input, Output: TArray<TPIXEL_RGBA>;
  Sound: array[0..1] of TArray<Single>;
  DLL: HMODULE;
  Init: TInitialize;
  Uninit: TUninitialize;
  GetTable: TGetTable;

procedure Check(Value: Boolean; const Msg: string);
begin
  Inc(Checks);
  if not Value then raise Exception.Create(Msg);
end;

procedure SetParam(const Name: string; Value: Double);
var
  P: PPointer;
  Item: PItemHeader;
begin
  P := PPointer(Table^.Items);
  while P^ <> nil do
  begin
    Item := P^;
    if string(Item^.Name) = Name then
    begin
      if string(Item^.ItemType) = 'track' then
        PFILTER_ITEM_TRACK(Item)^.Value := Value
      else if string(Item^.ItemType) = 'select' then
        PFILTER_ITEM_SELECT(Item)^.Value := Round(Value)
      else
        raise Exception.Create('Not a value parameter: ' + Name);
      Exit;
    end;
    Inc(P);
  end;
  raise Exception.Create('Missing parameter: ' + Name);
end;

procedure GetImage(Buffer: PPIXEL_RGBA); cdecl;
begin
  Move(Input[0], Buffer^, Length(Input) * SizeOf(TPIXEL_RGBA));
end;

procedure SetImage(Buffer: PPIXEL_RGBA; Width, Height: Integer); cdecl;
begin
  Check((Width = W) and (Height = H), 'output dimensions');
  SetLength(Output, Width * Height);
  Move(Buffer^, Output[0], Length(Output) * SizeOf(TPIXEL_RGBA));
  Inc(Writes);
end;

procedure GetSound(Buffer: PSingle; Channel: Integer); cdecl;
begin
  Check((Channel >= 0) and (Channel <= 1), 'audio get channel');
  FillChar(Buffer^, Obj.SampleNum * SizeOf(Single), 0);
end;

procedure SetSound(Buffer: PSingle; Channel: Integer); cdecl;
begin
  Check((Channel >= 0) and (Channel <= 1), 'audio set channel');
  SetLength(Sound[Channel], Obj.SampleNum);
  Move(Buffer^, Sound[Channel][0], Obj.SampleNum * SizeOf(Single));
  Inc(AudioWrites);
end;

{$OVERFLOWCHECKS OFF}
function ImageHash: UInt64;
var
  B: PByte;
  I: Integer;
begin
  Result := UInt64($CBF29CE484222325);
  B := @Output[0];
  for I := 0 to Length(Output) * SizeOf(TPIXEL_RGBA) - 1 do
  begin
    Result := (Result xor B^) * UInt64($100000001B3);
    Inc(B);
  end;
end;
{$OVERFLOWCHECKS ON}

function RenderFrame(Frame: Integer): UInt64;
var
  X, Y, I: Integer;
begin
  Obj.Frame := Frame;
  Obj.Time := Frame / 30;
  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
    begin
      I := Y * W + X;
      Input[I].R := Byte((X + Frame * 3) mod 256);
      Input[I].G := Byte((Y + Frame * 5) mod 256);
      Input[I].B := Byte((X + Y + Frame * 7) mod 256);
      Input[I].A := 255;
    end;
  Writes := 0;
  Check(Table^.Func_Proc_Video(@Video) = 1, 'video callback success');
  Check(Writes = 1, 'exactly one valid output write');
  for I := 0 to High(Output) do Check(Output[I].A = 255, 'opaque output');
  Result := ImageHash;
end;

procedure VideoTests;
const
  Frames: array[0..11] of Integer = (0, 7, 14, 15, 44, 45, 48, 52, 53, 64, 79, 110);
var
  Kind, Direction, I: Integer;
  Baseline: array[0..11] of UInt64;
  States: array[0..7] of UInt64;
  Saved: TFILTER_PROC_VIDEO;
  Second: Pointer;
begin
  SetParam('拡大率', 40);
  for Kind := 0 to 3 do
    for Direction := 0 to 1 do
    begin
      SetParam('カメラ種類', Kind);
      SetParam('カメラ方向', Direction);
      for I := 0 to High(Frames) do Baseline[I] := RenderFrame(Frames[I]);
      States[Kind * 2 + Direction] := Baseline[3];
      for I := High(Frames) downto 0 do
        Check(Baseline[I] = RenderFrame(Frames[I]), 'reverse video identical hash');
    end;
  for Kind := 0 to 2 do
    Check(States[Kind * 2] <> States[(Kind + 1) * 2], 'camera styles differ');
  Check(States[0] <> States[1], 'phone orientations differ');
  SetParam('カメラ種類', 0);
  SetParam('カメラ方向', 0);
  Second := Table^.Func_Create(2);
  Check(Second <> nil, 'second object session created');
  try
    Baseline[0] := RenderFrame(15);
    Saved := Video;
    Video.UserData := Second;
    Check(Baseline[0] = RenderFrame(15), 'separate session same deterministic input');
    Video := Saved;
  finally
    Table^.Func_Destroy(2, Second);
  end;
  Check(Table^.Func_Proc_Video(nil) = 1, 'nil video safe');
  Saved := Video;
  Video.Object_ := nil;
  Check(Table^.Func_Proc_Video(@Video) = 1, 'nil video object safe');
  Video := Saved;
  Video.UserData := nil;
  Check(Table^.Func_Proc_Video(@Video) = 1, 'nil video userdata safe');
  Video := Saved;
  Video.GetImageData := nil;
  Check(Table^.Func_Proc_Video(@Video) = 1, 'nil image getter safe');
  Video := Saved;
  Video.SetImageData := nil;
  Check(Table^.Func_Proc_Video(@Video) = 1, 'nil image setter safe');
  Video := Saved;
  Table^.Func_Destroy(999, nil);
end;

procedure AudioBlock(Start: Int64; N: Integer);
var
  Ch, I: Integer;
begin
  Obj.SampleIndex := Start;
  Obj.SampleNum := N;
  AudioWrites := 0;
  for Ch := 0 to 1 do
  begin
    SetLength(Sound[Ch], N);
    for I := 0 to N - 1 do Sound[Ch][I] := 0;
  end;
  Check(Table^.Func_Proc_Audio(@Audio) = 1, 'audio callback success');
  for Ch := 0 to 1 do
    for I := 0 to N - 1 do
      Check(not IsNan(Sound[Ch][I]) and (Abs(Sound[Ch][I]) <= 1),
        'finite clipped audio');
end;

procedure AudioTests;
var
  Kind, RateIndex, Rate, Capture, Total, Ch, I, J, Start, N: Integer;
  Whole: array[0..1] of TArray<Single>;
  Nonzero, Tail: Boolean;
  Saved: TAudio;
begin
  SetParam('登場時間', 15);
  SetParam('撮影待機時間', 30);
  SetParam('シャッター時間', 1);
  for RateIndex := 0 to 1 do
  begin
    if RateIndex = 0 then Rate := 44100 else Rate := 48000;
    Scene.SampleRate := Rate;
    Capture := Round(1.5 * Rate);
    Total := 2 * Rate;
    for Kind := 0 to 3 do
    begin
      SetParam('カメラ種類', Kind);
      SetParam('シャッター音量', 0);
      AudioBlock(Capture, 1024);
      Check(AudioWrites = 0, 'volume zero produces no writes');
      SetParam('シャッター音量', 100);
      AudioBlock(0, 1024);
      Check(AudioWrites = 0, 'pre-shutter produces no writes');
      AudioBlock(Capture - 128, Total);
      Check(AudioWrites = 2, 'both channels written');
      Nonzero := False;
      Tail := False;
      for Ch := 0 to 1 do
      begin
        Whole[Ch] := Copy(Sound[Ch]);
        for I := 0 to 127 do Check(Whole[Ch][I] = 0, 'leading silence');
        for I := 128 to Total - 1 do
        begin
          if Abs(Whole[Ch][I]) > 0.0001 then
          begin
            Nonzero := True;
            if I > 128 + Rate div 30 then Tail := True;
          end;
        end;
      end;
      Check(Nonzero, 'decoded style sound nonzero');
      Check(Tail, 'sound tail exceeds one-frame shutter effect');
      for J := (Total - 1) div 4096 downto 0 do
      begin
        Start := J * 4096;
        N := Min(4096, Total - Start);
        AudioBlock(Capture - 128 + Start, N);
        for Ch := 0 to 1 do
          for I := 0 to N - 1 do
            Check(Sound[Ch][I] = Whole[Ch][Start + I], 'reverse audio blocks exact');
      end;
    end;
  end;
  Check(Table^.Func_Proc_Audio(nil) = 1, 'nil audio safe');
  Saved := Audio;
  Audio.Scene := nil;
  Check(Table^.Func_Proc_Audio(@Audio) = 1, 'nil audio scene safe');
  Audio := Saved;
  Audio.Object_ := nil;
  Check(Table^.Func_Proc_Audio(@Audio) = 1, 'nil audio object safe');
  Audio := Saved;
  Audio.GetSampleData := nil;
  Check(Table^.Func_Proc_Audio(@Audio) = 1, 'nil audio getter safe');
  Audio := Saved;
  Audio.SetSampleData := nil;
  Check(Table^.Func_Proc_Audio(@Audio) = 1, 'nil audio setter safe');
  Audio := Saved;
end;

procedure Run;
var
  Path: string;
  Session: Pointer;
begin
  Path := ExpandFileName(ExtractFilePath(ParamStr(0)) +
    '..\..\Win64\Debug\SYNC_PhotoShot.auf2');
  if ParamCount > 0 then Path := ExpandFileName(ParamStr(1));
  DLL := LoadLibrary(PChar(Path));
  Check(DLL <> 0, 'LoadLibrary: ' + Path);
  try
    Init := TInitialize(GetProcAddress(DLL, 'InitializePlugin'));
    Uninit := TUninitialize(GetProcAddress(DLL, 'UninitializePlugin'));
    GetTable := TGetTable(GetProcAddress(DLL, 'GetFilterPluginTable'));
    Check(Assigned(Init) and Assigned(Uninit) and Assigned(GetTable), 'exports');
    // Nicomea と同じ通常フィルター形式。aux2 用 exports が無いことを正常とする。
    Check(GetProcAddress(DLL, 'RegisterPlugin') = nil, 'no auxiliary RegisterPlugin export');
    Check(GetProcAddress(DLL, 'GetCommonPluginTable') = nil, 'no auxiliary common table export');
    Check(GetProcAddress(DLL, 'RequiredVersion') = nil, 'no auxiliary version export');
    Check(GetProcAddress(DLL, 'PhotoShotSetPreparationSilent') = nil, 'no test-control export');
    Check(GetProcAddress(DLL, 'PhotoShotPreparationState') = nil, 'no test-state export');
    Check(Init(2010300) = 0, 'reject unsupported host without leaving partial state');
    Check(Init(2011600) = 1, 'supported initialization recovers after old-host refusal');
    try
      Table := GetTable;
      Check(Table <> nil, 'filter table');
      Check(string(Table^.Name) = '写真撮影', 'plugin name');
      Check(string(Table^.Label_) = 'SYNC', 'plugin group');
      Check(Assigned(Table^.Func_Create) and Assigned(Table^.Func_Destroy) and
        Assigned(Table^.Func_Proc_Video) and Assigned(Table^.Func_Proc_Audio), 'callbacks');
      Scene := Default(TSCENE_INFO);
      Scene.Width := W; Scene.Height := H;
      Scene.Rate := 30; Scene.Scale := 1; Scene.SampleRate := 44100;
      Obj := Default(TOBJECT_INFO);
      Obj.Width := W; Obj.Height := H; Obj.FrameTotal := 150;
      Obj.ChannelNum := 2; Obj.EffectID := 1; Obj.ID := 1;
      Session := Table^.Func_Create(1);
      Check(Session <> nil, 'create session');
      try
        Video := Default(TFILTER_PROC_VIDEO);
        Video.Scene := @Scene; Video.Object_ := @Obj; Video.UserData := Session;
        Video.GetImageData := GetImage; Video.SetImageData := SetImage;
        Audio := Default(TAudio);
        Audio.Scene := @Scene; Audio.Object_ := @Obj;
        Audio.GetSampleData := GetSound; Audio.SetSampleData := SetSound;
        SetLength(Input, W * H);
        VideoTests;
        AudioTests;
      finally
        Table^.Func_Destroy(1, Session);
      end;
    finally
      Uninit;
    end;
  finally
    FreeLibrary(DLL);
    DLL := 0;
  end;
end;

begin
  try
    Run;
    Writeln('PASS: ', Checks, ' mock-host assertions. DLL unloaded.');
    Writeln('This validates a mocked SDK ABI, not actual AviUtl2 host behavior.');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
