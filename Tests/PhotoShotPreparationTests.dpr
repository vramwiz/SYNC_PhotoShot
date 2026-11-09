program PhotoShotPreparationTests;
{$APPTYPE CONSOLE}
{$ALIGN 8}
{$POINTERMATH ON}

// 通常 3 exports の auf2 を独立 EXE で検証する。補助 plugin は作成しない。
// hidden-window 通知の message pump は行わず、テスト中の dialog 表示を避ける。
uses
  System.SysUtils, Winapi.Windows,
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas',
  SYNC_PhotoShot_HostAPI in '..\Source\Lib\SYNC_PhotoShot_HostAPI.pas';
type
  TInit = function(Version: Cardinal): Byte; cdecl;
  TDone = procedure; cdecl;
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;
  THeader = record Kind, Name: PWideChar; end;
  PHeader = ^THeader;
var
  Checks, WriteCount, CursorCount, CursorLayer, CursorFrame: Integer;
  Width, Height: Integer;
  Table: PFILTER_PLUGIN_TABLE;
  Scene: TSCENE_INFO;
  Obj: TOBJECT_INFO;
  Video: TFILTER_PROC_VIDEO;
  Edit: TPhotoShotEditSection;
  Info: TEDIT_INFO;
  Input, Output: TArray<TPIXEL_RGBA>;
  Init:TInit; Done:TDone; GetTable:TGetTable;
  DLL:HMODULE;
  Sessions:array[1..3]of Pointer;
  PrepareButton, ClearButton:TPhotoShotButtonCallback2;
  CursorReentry: Boolean;
  CursorReentryCount: Integer;

procedure Check(B:Boolean;const M:string);
begin Inc(Checks);if not B then raise Exception.Create(M);end;

procedure SetParam(const Name:string;Value:Double);
var P:PPointer;Item:PHeader;
begin
  P:=PPointer(Table^.Items);
  while P^<>nil do begin
    Item:=P^;
    if string(Item^.Name)=Name then begin
      if string(Item^.Kind)='track' then PFILTER_ITEM_TRACK(Item)^.Value:=Value
      else if string(Item^.Kind)='select' then PFILTER_ITEM_SELECT(Item)^.Value:=Round(Value)
      else raise Exception.Create('Wrong param type');
      Exit;
    end;Inc(P);
  end;raise Exception.Create('Missing param '+Name);
end;

procedure FindButtons;
var P:PPointer;Item:PHeader;
begin
  P:=PPointer(Table^.Items);
  while P^<>nil do begin
    Item:=P^;
    if string(Item^.Name)='写真を準備' then
      PrepareButton:=TPhotoShotButtonCallback2(PFILTER_ITEM_BUTTON(Item)^.Callback2);
    if string(Item^.Name)='写真を破棄（全て）' then
      ClearButton:=TPhotoShotButtonCallback2(PFILTER_ITEM_BUTTON(Item)^.Callback2);
    Inc(P);
  end;
end;

function ObjectRange(O:Pointer):TOBJECT_LAYER_FRAME;cdecl;
begin Result.Layer:=Integer(NativeUInt(O));Result.StartFrame:=10;Result.EndFrame:=200;end;
function FindEffect(O:Pointer;Name:PWideChar):Pointer;cdecl;
begin
  if string(Name)='写真撮影' then Result:=Pointer(NativeUInt(O)+10)
  else if string(Name)='写真撮影:2' then Result:=Pointer(NativeUInt(O)+20)
  else Result:=nil;
end;
function ObjectID(O:Pointer):Int64;cdecl;
begin Result:=NativeUInt(O)+100;end;
function EffectID(E:Pointer):Int64;cdecl;
begin Result:=NativeUInt(E)+1000;end;
procedure RenderInput(Index,Frame:Integer;R,G,B:Byte); forward;
procedure SetCursor(Layer,Frame:Integer);cdecl;
begin
  Inc(CursorCount);CursorLayer:=Layer;CursorFrame:=Frame;
  if CursorReentry then
  begin
    CursorReentry:=False;
    Inc(CursorReentryCount);
    // SDK の編集カーソル移動から通常描画が同期再入する場合を再現する。
    RenderInput(1,Frame-10,200,40,20);
  end;
end;
procedure GetImage(B:PPIXEL_RGBA);cdecl;
begin Move(Input[0],B^,Length(Input)*4);end;
procedure SetImage(B:PPIXEL_RGBA;W,H:Integer);cdecl;
begin
  Check((W=Width)and(H=Height),'valid output size');
  SetLength(Output,W*H);Move(B^,Output[0],Length(Output)*4);Inc(WriteCount);
end;
procedure Resize(W,H:Integer);
begin
  Width:=W;Height:=H;Scene.Width:=W;Scene.Height:=H;Obj.Width:=W;Obj.Height:=H;
  Info.Width:=W;Info.Height:=H;SetLength(Input,W*H);
end;
procedure FillColor(R,G,B:Byte);
var I:Integer;
begin
  for I:=0 to High(Input)do begin
    Input[I].R:=R;Input[I].G:=G;Input[I].B:=B;Input[I].A:=255;
  end;
end;
procedure UseObject(Index,Frame:Integer);
begin
  if Index=3 then begin Obj.ID:=101;Obj.EffectID:=1021;Obj.Layer:=1;end
  else begin Obj.ID:=100+Index;Obj.EffectID:=1010+Index;Obj.Layer:=Index;end;
  Obj.EffectLayer:=Obj.Layer;
  Obj.FrameS:=10;Obj.FrameE:=200;Obj.Frame:=Frame;Obj.FrameTotal:=191;
  // SDK v2.1.15 OBJECT_INFO origin_frame は offset 100。
  PInteger(NativeUInt(@Obj)+100)^:=10+Frame;
  Info.Frame:=10+Frame;Info.Layer:=Obj.Layer;
  Video.UserData:=Sessions[Index];
end;
procedure BeginPhoto(Index:Integer);
var N:Integer;
begin
  N:=CursorCount;
  if Index=3 then PrepareButton(@Edit,Pointer(1),'写真撮影:2','写真を準備')
  else PrepareButton(@Edit,Pointer(Index),'写真撮影','写真を準備');
  Check(CursorCount=N+1,'prepare moves cursor once');
  Check(CursorFrame=55,'prepare absolute frame');
  if Index=3 then Check(CursorLayer=1,'second effect cursor layer')
  else Check(CursorLayer=Index,'cursor layer');
end;
procedure ClearPhotos;
begin ClearButton(@Edit,Pointer(1),'写真撮影','写真を破棄（全て）');end;
procedure DrawCurrent;
begin
  WriteCount:=0;Check(Table^.Func_Proc_Video(@Video)=1,'video succeeds');
  Check(WriteCount=1,'normal render produces image even while capturing');
end;
procedure RenderInput(Index,Frame:Integer;R,G,B:Byte);
begin UseObject(Index,Frame);FillColor(R,G,B);DrawCurrent;end;
function CenterMatches(R,G,B:Byte):Boolean;
var P:TPIXEL_RGBA;
begin
  P:=Output[(Height div 2)*Width+Width div 2];
  Result:=(Abs(Integer(P.R)-R)<=2)and(Abs(Integer(P.G)-G)<=2)and
    (Abs(Integer(P.B)-B)<=2);
end;
procedure PreviewColor(Index:Integer;R,G,B:Byte);
begin
  RenderInput(Index,120,20,30,200);
  Check(CenterMatches(R,G,B),'preview uses captured source, not current input or processed background');
end;
procedure NotPrepared(Index:Integer);
begin
  RenderInput(Index,120,20,30,200);
  Check(not CenterMatches(200,40,20),'no prepared snapshot is fabricated');
end;

procedure Tests;
begin
  Check(Assigned(PrepareButton)and Assigned(ClearButton),'normal filter buttons');
  SetParam('プレビュー方式',0);SetParam('プレビュー演出',0);
  SetParam('背景暗さ',70);SetParam('内部ぼかし',0);
  SetParam('登場時間',15);SetParam('撮影待機時間',30);
  // 描画だけでは写真を準備したことにしない。
  ClearPhotos;RenderInput(1,45,200,40,20);NotPrepared(1);
  BeginPhoto(1);RenderInput(1,45,200,40,20);PreviewColor(1,200,40,20);
  // 別 object および同 object の別 effect がそれぞれ異なる写真を所有。
  BeginPhoto(2);RenderInput(2,45,40,180,70);
  BeginPhoto(3);RenderInput(3,45,180,40,160);
  PreviewColor(1,200,40,20);PreviewColor(2,40,180,70);PreviewColor(3,180,40,160);
  // SetCursor が返る前に video が再入しても deadlock せず写真を確定できる。
  ClearPhotos;CursorReentryCount:=0;CursorReentry:=True;
  BeginPhoto(1);
  Check(CursorReentryCount=1,'cursor invokes synchronous video callback once');
  PreviewColor(1,200,40,20);
  // pending 対象の破棄は要求も取り消す。他 effect にその要求を流用しない。
  ClearPhotos;BeginPhoto(1);
  Table^.Func_Destroy(1011,Sessions[1]);Sessions[1]:=nil;
  RenderInput(3,45,200,40,20);NotPrepared(3);
  // 同じ ID の session を作り直しても古い要求が復活しない。
  Sessions[1]:=Table^.Func_Create(1011);Check(Sessions[1]<>nil,'replacement session');
  RenderInput(1,45,200,40,20);NotPrepared(1);
  // 同対象の再準備は古い写真を破棄し、新しい入力のみ確定する。
  BeginPhoto(1);NotPrepared(1);RenderInput(1,45,150,100,30);PreviewColor(1,150,100,30);
  ClearPhotos;BeginPhoto(1);ClearPhotos;RenderInput(1,45,200,40,20);NotPrepared(1);
  // 新しい要求は古い pending をキャンセルし、対象を切り替える。
  BeginPhoto(1);BeginPhoto(2);RenderInput(1,45,200,40,20);NotPrepared(1);
  RenderInput(2,45,40,180,70);PreviewColor(2,40,180,70);
  // wrong relative / absolute / origin / scene / effect / reference render を拒否する。
  ClearPhotos;BeginPhoto(1);RenderInput(1,44,200,40,20);NotPrepared(1);
  ClearPhotos;BeginPhoto(1);UseObject(1,45);Obj.FrameS:=11;
  FillColor(200,40,20);DrawCurrent;NotPrepared(1);
  ClearPhotos;BeginPhoto(1);UseObject(1,45);
  PInteger(NativeUInt(@Obj)+100)^:=56;FillColor(200,40,20);DrawCurrent;NotPrepared(1);
  ClearPhotos;BeginPhoto(1);Scene.ID:=8;RenderInput(1,45,200,40,20);
  Scene.ID:=7;NotPrepared(1);
  ClearPhotos;BeginPhoto(1);Scene.OriginID:=8;RenderInput(1,45,200,40,20);
  Scene.OriginID:=7;NotPrepared(1);
  ClearPhotos;BeginPhoto(1);Scene.Flag:=1;RenderInput(1,45,200,40,20);
  Scene.Flag:=0;NotPrepared(1);
  ClearPhotos;BeginPhoto(1);UseObject(1,45);Info.Frame:=54;
  FillColor(200,40,20);DrawCurrent;NotPrepared(1);
  ClearPhotos;BeginPhoto(1);RenderInput(3,45,200,40,20);NotPrepared(1);
  // 準備済み画像の寸法と現在入力の寸法が変わったら、その写真を利用しない。
  ClearPhotos;BeginPhoto(1);RenderInput(1,45,200,40,20);PreviewColor(1,200,40,20);
  Resize(160,90);NotPrepared(1);Resize(320,180);
  ClearPhotos;
end;

procedure Run;
var Path:string;I:Integer;
begin
  Path:=ExpandFileName(ExtractFilePath(ParamStr(0))+'..\..\Win64\Debug\SYNC_PhotoShot.auf2');
  if ParamCount>0 then Path:=ExpandFileName(ParamStr(1));
  DLL:=LoadLibrary(PChar(Path));Check(DLL<>0,'load normal auf2');
  try
    Init:=TInit(GetProcAddress(DLL,'InitializePlugin'));
    Done:=TDone(GetProcAddress(DLL,'UninitializePlugin'));
    GetTable:=TGetTable(GetProcAddress(DLL,'GetFilterPluginTable'));
    Check(Assigned(Init)and Assigned(Done)and Assigned(GetTable),'3 exports');
    Check(GetProcAddress(DLL,'RegisterPlugin')=nil,'no aux2 registration');
    Check(GetProcAddress(DLL,'PhotoShotPreparationState')=nil,'no test helper export');
    Check(Init(2011500)=1,'initialize');
    try
      Table:=GetTable;Check(Table<>nil,'filter table');FindButtons;
      Info.SceneID:=7;Edit.Base.Info:=@Info;Edit.Base.GetObjectLayerFrame:=ObjectRange;
      Edit.Base.SetCursorLayerFrame:=@SetCursor;Edit.FindEffect:=FindEffect;
      Edit.GetObjectID:=ObjectID;Edit.GetEffectID:=EffectID;
      Scene.Rate:=30;Scene.Scale:=1;Scene.SampleRate:=44100;
      Scene.ID:=7;Scene.OriginID:=7;Scene.Flag:=0;
      Video.Scene:=@Scene;Video.Object_:=@Obj;Video.Edit:=@Edit.Base;
      Video.GetImageData:=GetImage;Video.SetImageData:=SetImage;
      Resize(320,180);
      Sessions[1]:=Table^.Func_Create(1011);Sessions[2]:=Table^.Func_Create(1012);
      Sessions[3]:=Table^.Func_Create(1021);
      for I:=1 to 3 do Check(Sessions[I]<>nil,'session');
      try Tests;finally
        Table^.Func_Destroy(1011,Sessions[1]);Table^.Func_Destroy(1012,Sessions[2]);
        Table^.Func_Destroy(1021,Sessions[3]);
      end;
    finally Done;end;
  finally FreeLibrary(DLL);DLL:=0;end;
end;
begin
  try Run;Writeln('PASS: ',Checks,' normal-auf2 preparation mock assertions. Module unloaded.');
    Writeln('Independent EXE only; not actual AviUtl2 behavior. No message pumping.');
  except on E:Exception do begin Writeln('FAIL: ',E.Message);Halt(1);end;end;
end.
