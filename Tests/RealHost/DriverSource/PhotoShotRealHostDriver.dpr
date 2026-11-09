library PhotoShotRealHostDriver;

// Isolated portable-host verification only. Never deploy this driver to ProgramData.
// Timer operations create a fresh synthetic test scene in this dedicated host process.
{$ALIGN 8}
uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.IOUtils,
  AviUtl2FilterTypes, SYNC_PhotoShot_HostAPI;

type
  TCreateProject = function(W,H,Rate,Scale,SampleRate:Integer;
    Background:TPIXEL_RGBA; ShowConfirm:Byte):Byte; cdecl;
  TCreateAlias = function(Alias:PAnsiChar; Layer,Frame,Length_:Integer):OBJECT_HANDLE; cdecl;
  TSceneAudioCallback = procedure(Param:Pointer; Frame:Integer;
    L,R:PSingle; Count:Integer); cdecl;
  TRenderAudio = function(Frame:Integer; Param:Pointer;
    Callback:TSceneAudioCallback):Byte; cdecl;
  TGetTable = function:PFILTER_PLUGIN_TABLE; cdecl;
  TSilent = procedure(Value:Byte); cdecl;
  TState = function:Integer; cdecl;
  PButton = ^TFILTER_ITEM_BUTTON;
var
  Edit:PPhotoShotEditHandle;
  Window:HWND;
  Root:string;
  Stage,TickCount,Pending:Integer;
  TargetEffectID:Int64;
  PrepareButton:TPhotoShotButtonCallback2;
  QueryState:TState;
  Table:TFILTER_PLUGIN_TABLE;
  Items:array[0..0] of Pointer;
  Common:TPhotoShotCommonPluginTable;
  FrameHashes:array[0..3] of UInt64;
const
  Frames:array[0..3] of Integer=(120,80,120,80);
function API(Base:Pointer; Offset:NativeUInt):Pointer;
begin Result:=PPointer(NativeUInt(Base)+Offset)^; end;
procedure Log(const S:string);
begin
  TFile.AppendAllText(Root+'Results\driver.log',FormatDateTime('hh:nn:ss.zzz',Now)+' '+S+sLineBreak,TEncoding.UTF8);
end;
procedure Fail(const S:string);
begin Log('FAIL '+S); Stage:=99; KillTimer(Window,1); end;
function BackgroundVideo(Video:PFILTER_PROC_VIDEO):Byte;cdecl;
var Pixels:TArray<TPIXEL_RGBA>; X,Y,W,H,F:Integer; P:NativeInt;
begin
  Result:=1;
  try
    if (Video=nil) or (Video^.Scene=nil) or (Video^.Object_=nil) then Exit;
    W:=Video^.Scene^.Width;H:=Video^.Scene^.Height;F:=Video^.Object_^.Frame;
    if (W<=0) or (H<=0) or (Int64(W)*H>1048576) then Exit;
    SetLength(Pixels,W*H);
    for Y:=0 to H-1 do for X:=0 to W-1 do
    begin
      P:=NativeInt(Y)*W+X;
      Pixels[P].R:=Byte((X+F*3) and 255);
      Pixels[P].G:=Byte((Y+F*7) and 255);
      Pixels[P].B:=Byte((X div 16 xor Y div 16)*32 and 255);
      Pixels[P].A:=255;
    end;
    Video^.SetImageData(@Pixels[0],W,H);
  except on E:Exception do Log('background exception '+E.Message);end;
end;
procedure SetupScene(S:PPhotoShotEditSection);cdecl;
var B,O:OBJECT_HANDLE; Alias:UTF8String; E:EFFECT_HANDLE;
begin
  try
    Alias:=UTF8String('[Object]'+sLineBreak+'[Object.0]'+sLineBreak+
      'effect.name=PhotoShot Test Background'+sLineBreak+
      '[Object.1]'+sLineBreak+'effect.name=標準描画'+sLineBreak);
    B:=TCreateAlias(S^.Base.CreateObjectFromAlias)(PAnsiChar(Alias),0,0,180);
    Alias:=UTF8String('[Object]'+sLineBreak+'[Object.0]'+sLineBreak+
      'effect.name=フィルタオブジェクト'+sLineBreak+
      '[Object.1]'+sLineBreak+'effect.name=写真撮影'+sLineBreak);
    O:=TCreateAlias(S^.Base.CreateObjectFromAlias)(PAnsiChar(Alias),1,0,180);
    if (B=nil) or (O=nil) then begin Fail('Unable to create synthetic objects');Exit;end;
    E:=S^.FindEffect(O,'写真撮影');TargetEffectID:=S^.GetEffectID(E);
    Log('created effect ID '+IntToStr(TargetEffectID));
    if TargetEffectID=0 then begin Fail('effect ID unavailable');Exit;end;
    if not Assigned(PrepareButton) then begin Fail('prepare button unavailable');Exit;end;
    PrepareButton(S,O,'写真撮影','写真を準備');
  except on X:Exception do Fail('SetupScene '+X.Message);end;
end;
procedure UpdateOnly(S:PPhotoShotEditSection);cdecl;
var O:OBJECT_HANDLE;
begin
  O:=S^.Base.FindObject(1,0);
  if O=nil then begin Fail('target missing on update');Exit;end;
  // Change a preparation-affecting parameter, then ask for a fresh snapshot.
  if not S^.Base.SetObjectItemValue(O,'写真撮影','内部X','20') then
  begin Fail('parameter edit failed');Exit;end;
  Log('updated 内部X=20; waiting for invalidation');
end;
procedure Reprepare(S:PPhotoShotEditSection);cdecl;
var O:OBJECT_HANDLE;
begin
  O:=S^.Base.FindObject(1,0);
  if O=nil then begin Fail('target missing on reprepare');Exit;end;
  PrepareButton(S,O,'写真撮影','写真を準備');
end;
procedure VideoDone(Param:Pointer;Frame:Integer;Buffer:Pointer;W,H,Pitch:Integer);cdecl;
var I,Y:Integer; Bytes:TBytes; Hash:UInt64; Index:Integer;
begin
  try
    Index:=NativeInt(Param);
    if (Buffer=nil) or (W<=0) or (H<=0) or (Pitch<W*4) then
    begin Fail('invalid rendered frame');Exit;end;
    SetLength(Bytes,W*H*4);
    for Y:=0 to H-1 do Move(PByte(NativeUInt(Buffer)+NativeUInt(Y*Pitch))^,Bytes[Y*W*4],W*4);
    Hash:=$CBF29CE484222325;
    for I:=0 to High(Bytes) do Hash:=(Hash xor UInt64(Bytes[I]))*UInt64($100000001B3);
    TFile.WriteAllBytes(Root+'Results\frame_'+IntToStr(Index)+'_'+IntToStr(Frame)+'.rgba',Bytes);
    TFile.WriteAllText(Root+'Results\frame_'+IntToStr(Index)+'.txt',
      Format('%d %d RGBA hash=%s',[W,H,IntToHex(Hash,16)]),TEncoding.UTF8);
    if Index<=3 then FrameHashes[Index]:=Hash;
    Log(Format('frame=%d index=%d hash=%s',[Frame,Index,IntToHex(Hash,16)]));
  except on X:Exception do Fail('VideoDone '+X.Message);end;
  InterlockedExchange(Pending,0);
end;
procedure AudioDone(Param:Pointer;Frame:Integer;L,R:PSingle;Count:Integer);cdecl;
var I:Integer;Peak:Single;
begin
  try
    Peak:=0;
    if (Count>0) and (Count<1000000) and (L<>nil) and (R<>nil) then
      for I:=0 to Count-1 do
      begin
        if Abs(PSingle(NativeUInt(L)+NativeUInt(I*4))^)>Peak then Peak:=Abs(PSingle(NativeUInt(L)+NativeUInt(I*4))^);
        if Abs(PSingle(NativeUInt(R)+NativeUInt(I*4))^)>Peak then Peak:=Abs(PSingle(NativeUInt(R)+NativeUInt(I*4))^);
      end;
    Log(Format('audio frame=%d count=%d peak=%s',[Frame,Count,FloatToStr(Peak)]));
    if Peak=0 then Log('UNCONFIRMED: standalone filter audio yielded silence');
  except on X:Exception do Fail('AudioDone '+X.Message);end;
  InterlockedExchange(Pending,0);
end;
function LocatePhotoShot:Boolean;
var M:HMODULE; GetTable:TGetTable; F:PFILTER_PLUGIN_TABLE;
  P:PPointer; B:PButton; Silent:TSilent; I:Integer;
begin
  Result:=False;
  M:=GetModuleHandle('SYNC_PhotoShot.aux2');if M=0 then Exit;
  GetTable:=TGetTable(GetProcAddress(M,'GetFilterPluginTable'));if not Assigned(GetTable) then Exit;
  Silent:=TSilent(GetProcAddress(M,'PhotoShotSetPreparationSilent'));
  if not Assigned(Silent) then begin Fail('required PhotoShotSetPreparationSilent export missing');Exit;end;
  Silent(1);
  QueryState:=TState(GetProcAddress(M,'PhotoShotPreparationState'));
  F:=GetTable();if (F=nil) or (F^.Items=nil) then Exit;
  P:=PPointer(F^.Items);
  for I:=0 to 99 do
  begin
    if P^=nil then Break; B:=PButton(P^);
    if (string(B^.ItemType)='button') and (string(B^.Name)='写真を準備') then
    begin PrepareButton:=TPhotoShotButtonCallback2(B^.Callback2);Result:=Assigned(PrepareButton);Exit;end;
    Inc(P);
  end;
end;
procedure Tick;
var Color:TPIXEL_RGBA; State,I:Integer;
begin
  Inc(TickCount);
  if TickCount>600 then begin Fail('timeout');Exit;end;
  if Pending<>0 then Exit;
  case Stage of
    0: if LocatePhotoShot then begin
      Color:=Default(TPIXEL_RGBA);Color.A:=255;
      if TCreateProject(API(Edit,176))(320,180,30,1,44100,Color,0)=0 then Exit;
      Stage:=1;
    end;
    1: begin
      Stage:=2;
      if Edit^.CallEditSection(SetupScene)=0 then Fail('edit section rejected');
      TickCount:=0;
    end;
    2,12: begin
      if Assigned(QueryState) then begin
        State:=QueryState();
        if State=3 then begin Fail('preparation reported failure');Exit;end;
        if State<>2 then Exit;
      end else if TickCount<20 then Exit;
      if Stage=2 then Stage:=3 else Stage:=9;
    end;
    3..6: begin
      I:=Stage-3;InterlockedExchange(Pending,1);
      if Edit^.RenderingSceneVideo(Frames[I],Pointer(NativeInt(I)),VideoDone)=0 then
      begin InterlockedExchange(Pending,0);Fail('video task rejected');end
      else Inc(Stage);
    end;
    7: begin
      if (FrameHashes[0]<>FrameHashes[2]) or (FrameHashes[1]<>FrameHashes[3]) then
        Log('FAIL repeated-frame hashes differ') else Log('PASS repeat/seek image determinism');
      Stage:=8;TickCount:=0;
      if Edit^.CallEditSection(UpdateOnly)=0 then Fail('update edit section rejected');
    end;
    8: begin
      if TickCount<8 then Exit;
      if Assigned(QueryState) and (QueryState()<>0) then
      begin Fail('changed parameter did not invalidate preparation');Exit;end;
      Log('PASS parameter edit invalidated preparation');
      Stage:=12;TickCount:=0;
      if Edit^.CallEditSection(Reprepare)=0 then Fail('reprepare edit section rejected');
    end;
    9: begin
      InterlockedExchange(Pending,1);
      if Edit^.RenderingSceneVideo(120,Pointer(4),VideoDone)=0 then
      begin InterlockedExchange(Pending,0);Fail('post-update render rejected');end
      else Stage:=10;
    end;
    10: begin
      InterlockedExchange(Pending,1);
      if TRenderAudio(API(Edit,96))(45,nil,AudioDone)=0 then
      begin InterlockedExchange(Pending,0);Log('UNCONFIRMED audio task rejected');end;
      Stage:=11;
    end;
    11: begin
      Log('DONE; host left open for coordinator inspection');
      Stage:=99;KillTimer(Window,1);
    end;
  end;
end;
function WndProc(W:HWND;Msg:UINT;WP:WPARAM;LP:LPARAM):LRESULT;stdcall;
begin
  if Msg=WM_TIMER then begin
    try Tick; except on E:Exception do Fail(E.Message);end;
    Exit(0);
  end;
  Result:=DefWindowProc(W,Msg,WP,LP);
end;
function RequiredVersion:Cardinal;cdecl;
begin Result:=2011500;end;
function GetCommonPluginTable:PPhotoShotCommonPluginTable;cdecl;
begin Common.Name:='PhotoShot isolated host test';Common.Information:='Test driver; not for normal installation';Result:=@Common;end;
procedure RegisterPlugin(Host:PPhotoShotHostAppTable);cdecl;
var WC:WNDCLASSEX;Buf:array[0..32767] of WideChar;
begin
  try
    GetModuleFileName(0,Buf,Length(Buf));Root:=ExtractFilePath(string(Buf));
    if not DirectoryExists(Root+'Results') then Exit;
    Common.Name:='PhotoShot isolated host test';Common.Information:='Test driver; not for normal installation';
    Table:=Default(TFILTER_PLUGIN_TABLE);Table.Flag:=1 or 4;
    Table.Name:='PhotoShot Test Background';Table.Label_:='PhotoShotTests';
    Table.Items:=@Items[0];Table.Func_Proc_Video:=BackgroundVideo;
    Host^.RegisterFilterPlugin(@Table);Edit:=Host^.CreateEditHandle;
    WC:=Default(WNDCLASSEX);WC.cbSize:=SizeOf(WC);WC.lpfnWndProc:=@WndProc;
    WC.hInstance:=HInstance;WC.lpszClassName:='PhotoShotIsolatedTestDispatcher';
    RegisterClassEx(WC);
    Window:=CreateWindowEx(0,WC.lpszClassName,'',0,0,0,0,0,HWND_MESSAGE,0,HInstance,nil);
    if Window=0 then Exit;
    Log('driver registered; timer queued');SetTimer(Window,1,250,nil);
  except on E:Exception do OutputDebugString(PChar(E.Message));end;
end;
procedure UninitializePlugin;cdecl;
begin
  if Window<>0 then begin KillTimer(Window,1);DestroyWindow(Window);Window:=0;end;
end;
exports RequiredVersion,GetCommonPluginTable,RegisterPlugin,UninitializePlugin;
begin
end.
