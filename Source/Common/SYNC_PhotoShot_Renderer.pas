unit SYNC_PhotoShot_Renderer;

// 写真撮影の合成描画。ホスト API と時間順序に依存せず、渡された現在画像と
// シャッター時刻画像から毎回同じ結果を生成する。画像所有権は公開 API に記載。
interface

uses
  Winapi.Windows, Winapi.GDIPAPI, Winapi.GDIPOBJ,
  SYNC_SmartphoneRenderer, SYNC_PhotoShot_Timeline;

type
  PPhotoShotSettings = ^TPhotoShotSettings;

  TPhotoShotRenderer = class
  private
    FToken: ULONG_PTR;
    FPhone: TSmartphoneRenderer;
    FOutput: TGPBitmap;
  public
    // GDI+ を開始。1 インスタンスを複数スレッドから同時に呼ばない。
    constructor Create;
    // 戻り画像を含む所有資源を解放する。借用入力画像は解放しない。
    destructor Destroy; override;
    // Current/Snapshot は呼出側所有。Snapshot は同一効果のシャッター時刻画像。
    // 戻り値は本インスタンス所有 PARGB 画像。次の Render または Destroy まで有効。
    // 入力 nil は nil を返す。Snapshot nil 時は写真を捏造せずプレビューを省略する。
    // CapturedSettings は撮影時の内側設定・画角を借用する。nil は既存動作。
    // 写真枠・プレビュー姿勢・背景は現在 Settings を使用し、ポインターは保持しない。
    function Render(Current, Snapshot: TGPBitmap; const Settings: TPhotoShotSettings;
      Frame: Integer; CapturedSettings: PPhotoShotSettings = nil): TGPBitmap;
  end;

// カメラ画面の画面上領域を入力から採取する。本体と写真で共用し、UIを含まない。
// Source は借用、戻り値は呼出側が Free。範囲外とゼロ倍率は不透明黒。
// Pose は実描画姿勢、S は画角・内部設定。座標は入力画像の左上を原点とする。
function RenderPhotoShotView(Source:TGPBitmap; const S:TPhotoShotSettings;
  const Pose:TPhotoShotState; W,H:Integer):TGPBitmap;
implementation

uses
  System.SysUtils, System.Math, System.Types;

type
  TBytes = TArray<Byte>;

procedure RequireGdi(Status:TStatus; const Operation:string);
begin
  if Status<>Ok then
    raise Exception.CreateFmt('PhotoShot GDI+ %s failed: status %d',[Operation,Ord(Status)]);
end;
function NewBitmap(W, H: Integer): TGPBitmap;
begin
  Result := TGPBitmap.Create(Max(1, W), Max(1, H), PixelFormat32bppPARGB);
  if Result.GetLastStatus <> Ok then
  begin
    Result.Free;
    raise Exception.Create('PhotoShot bitmap allocation failed');
  end;
end;

procedure Fill(G: TGPGraphics; X, Y, W, H: Single; Color: ARGB);
var B: TGPSolidBrush;
begin
  if (W <= 0) or (H <= 0) then Exit;
  B := TGPSolidBrush.Create(Color);
  try G.FillRectangle(B, X, Y, W, H); finally B.Free; end;
end;

procedure RoundFill(G: TGPGraphics; X, Y, W, H, R: Single; Color: ARGB);
var P: TGPGraphicsPath; B: TGPSolidBrush; D: Single;
begin
  P := TGPGraphicsPath.Create;
  B := TGPSolidBrush.Create(Color);
  try
    D := Min(R * 2, Min(W, H));
    P.AddArc(X, Y, D, D, 180, 90);
    P.AddArc(X + W - D, Y, D, D, 270, 90);
    P.AddArc(X + W - D, Y + H - D, D, D, 0, 90);
    P.AddArc(X, Y + H - D, D, D, 90, 90);
    P.CloseFigure;
    G.FillPath(B, P);
  finally B.Free; P.Free; end;
end;

procedure Ellipse(G: TGPGraphics; X,Y,W,H: Single; Color: ARGB);
var B: TGPSolidBrush;
begin
  B := TGPSolidBrush.Create(Color);
  try G.FillEllipse(B,X,Y,W,H); finally B.Free; end;
end;

procedure Caption(G: TGPGraphics; const S: string; X,Y,W,H,Size: Single; Color: ARGB);
var B: TGPSolidBrush; F: TGPFont; Format: TGPStringFormat;
begin
  F := TGPFont.Create('Segoe UI',Size,FontStyleRegular,UnitPixel);
  B := TGPSolidBrush.Create(Color);
  Format := TGPStringFormat.Create;
  try
    Format.SetAlignment(StringAlignmentCenter);
    Format.SetLineAlignment(StringAlignmentCenter);
    G.DrawString(S,Length(S),F,MakeRect(X,Y,W,H),Format,B);
  finally Format.Free; B.Free; F.Free; end;
end;

// 平行移動・回転・倍率は画像中心を基準にする。色行列で全体の不透明度だけを変更。
procedure Place(G: TGPGraphics; Image: TGPBitmap;
  CX,CY,Scale,Angle,Opacity,VerticalScale: Double);
var Saved: GraphicsState; A: TGPImageAttributes; M: TColorMatrix; I: Integer;
  W,H: Single;
begin
  if (Image=nil) or (Scale<=0) or (Opacity<=0) then Exit;
  W := Image.GetWidth; H := Image.GetHeight;
  A := TGPImageAttributes.Create;
  Saved := G.Save;
  try
    M := Default(TColorMatrix);
    for I:=0 to 4 do M[I,I]:=1;
    M[3,3] := EnsureRange(Opacity / 100,0.0,1.0);
    A.SetColorMatrix(M);
    G.TranslateTransform(CX,CY);
    G.RotateTransform(Angle);
    // 起き上がりは縦圧縮で近似する。終端は厳密に1となり通常描画と一致する。
    G.ScaleTransform(Scale,Scale * EnsureRange(VerticalScale,0.01,1.0));
    RequireGdi(G.DrawImage(Image,MakeRect(-W/2,-H/2,W,H),0,0,W,H,UnitPixel,A),'Place');
  finally G.Restore(Saved); A.Free; end;
end;

// 二方向ボックスぼかし。画像は複製せず処理し、半径 0 では完全な無加工。
// 各画素を一定回数だけ処理するため、半径に比例した処理時間の増大を避ける。
procedure Blur(Bitmap: TGPBitmap; Radius: Integer);
var Data: TBitmapData; Temp: TBytes; W,H,X,Y,C,K,Sum,Count,L,R: Integer;
  Row,OutRow: PByte;
begin
  W:=Bitmap.GetWidth; H:=Bitmap.GetHeight;
  Radius:=EnsureRange(Radius,0,128);
  if Radius=0 then Exit;
  if Bitmap.LockBits(MakeRect(0,0,W,H),ImageLockModeRead or ImageLockModeWrite,
    PixelFormat32bppPARGB,Data)<>Ok then Exit;
  try
    SetLength(Temp,NativeInt(W)*H*4);
    for Y:=0 to H-1 do
    begin
      Row:=PByte(NativeInt(Data.Scan0)+NativeInt(Y)*Data.Stride);
      for C:=0 to 3 do
      begin
        Sum:=0;
        for K:=0 to Min(Radius,W-1) do Inc(Sum,Row[K*4+C]);
        for X:=0 to W-1 do
        begin
          L:=Max(0,X-Radius); R:=Min(W-1,X+Radius); Count:=R-L+1;
          Temp[(NativeInt(Y)*W+X)*4+C]:=Sum div Count;
          if X-Radius>=0 then Dec(Sum,Row[(X-Radius)*4+C]);
          if X+Radius+1<W then Inc(Sum,Row[(X+Radius+1)*4+C]);
        end;
      end;
    end;
    for X:=0 to W-1 do
      for C:=0 to 3 do
      begin
        Sum:=0;
        for K:=0 to Min(Radius,H-1) do Inc(Sum,Temp[(NativeInt(K)*W+X)*4+C]);
        for Y:=0 to H-1 do
        begin
          L:=Max(0,Y-Radius); R:=Min(H-1,Y+Radius); Count:=R-L+1;
          OutRow:=PByte(NativeInt(Data.Scan0)+NativeInt(Y)*Data.Stride);
          OutRow[X*4+C]:=Sum div Count;
          if Y-Radius>=0 then Dec(Sum,Temp[(NativeInt(Y-Radius)*W+X)*4+C]);
          if Y+Radius+1<H then Inc(Sum,Temp[(NativeInt(Y+Radius+1)*W+X)*4+C]);
        end;
      end;
  finally Bitmap.UnlockBits(Data); end;
end;

procedure CameraGeometry(Kind,Orientation: Integer; out W,H: Integer; out Screen: TGPRectF);
begin
  if Kind=0 then
  begin
    SmartphoneSize(Orientation,W,H);
    Screen:=MakeRect(Single(14),Single(18),Single(W-28),Single(H-36));
  end
  else
  begin
    W:=700; H:=470;
    if Kind=2 then H:=500;
    if Kind=3 then begin W:=600; H:=650; end;
    Screen:=MakeRect(Single(46),Single(74),Single(W-172),Single(H-160));
    if Kind=3 then Screen:=MakeRect(Single(48),Single(102),Single(W-96),Single(350));
  end;
end;

// カメラ矩形から入力へのアフィン写像を逆に解き、入力画像の3頂点を出力へ写す。
// GPU/ホストの完成画像を逆取得せず、加工前入力を直接サンプリングする。
function RenderPhotoShotView(Source:TGPBitmap; const S:TPhotoShotSettings;
  const Pose:TPhotoShotState; W,H:Integer):TGPBitmap;
var G:TGPGraphics; BodyW,BodyH:Integer; Screen:TGPRectF;
  Scale,Vertical,Zoom,CosA,SinA,CenterX,CenterY,DX,DY,SpanX,SpanY:Double;
  Points:array[0..2] of TGPPointF;
  function ToOutput(X,Y:Double):TGPPointF;
  var LX,LY:Double;
  begin
    X:=X-CenterX; Y:=Y-CenterY;
    LX:=CosA*X+SinA*Y+S.InnerX;
    LY:=-SinA*X+CosA*Y+S.InnerY;
    Result:=MakePoint(Single(W*(0.5+LX/SpanX)),Single(H*(0.5+LY/SpanY)));
  end;
begin
  Result:=NewBitmap(W,H);
  try
  G:=TGPGraphics.Create(Result);
  try
    G.Clear($FF000000);
    Scale:=Pose.CameraScale/100;
    if (Source=nil) or (Scale<=0) or (Pose.CameraVerticalScale<=0) then Exit;
    CameraGeometry(S.CameraKind,S.Orientation,BodyW,BodyH,Screen);
    Vertical:=EnsureRange(Pose.CameraVerticalScale,0.01,1.0);
    Zoom:=Max(0.01,S.InnerZoom/100);
    CosA:=Cos(DegToRad(Pose.CameraRotation)); SinA:=Sin(DegToRad(Pose.CameraRotation));
    DX:=(Screen.X+Screen.Width/2-BodyW/2)*Scale;
    DY:=(Screen.Y+Screen.Height/2-BodyH/2)*Scale*Vertical;
    CenterX:=Source.GetWidth/2+Pose.CameraX+CosA*DX-SinA*DY;
    CenterY:=Source.GetHeight/2+Pose.CameraY+SinA*DX+CosA*DY;
    SpanX:=Screen.Width*Scale/Zoom;
    SpanY:=Screen.Height*Scale*Vertical/Zoom;
    Points[0]:=ToOutput(0,0); Points[1]:=ToOutput(Source.GetWidth,0);
    Points[2]:=ToOutput(0,Source.GetHeight);
    G.SetInterpolationMode(InterpolationModeHighQualityBicubic);
    G.SetPixelOffsetMode(PixelOffsetModeHalf);
    RequireGdi(G.DrawImage(Source,PGPPointF(@Points[0]),3,0,0,Single(Source.GetWidth),
      Single(Source.GetHeight),UnitPixel),'Sample view');
  finally G.Free; end;
  // 撮影時の内部ぼかしは写真にも残す。背景のぼかし・暗さは焼き込まない。
  Blur(Result,Round(EnsureRange(S.InnerBlur,0.0,100.0)*Min(W,H)/1000));
  except
    Result.Free;
    raise;
  end;
end;
procedure CameraUI(G: TGPGraphics; const Screen: TGPRectF; Kind,Orientation: Integer);
var P: TGPPen; CX,CY,R: Single;
begin
  CX:=Screen.X+Screen.Width/2; CY:=Screen.Y+Screen.Height/2; R:=Min(Screen.Width,Screen.Height)*0.12;
  P:=TGPPen.Create($CCFFFFFF,2);
  try
    G.DrawLine(P,CX-R,CY-R,CX-R/2,CY-R); G.DrawLine(P,CX-R,CY-R,CX-R,CY-R/2);
    G.DrawLine(P,CX+R,CY-R,CX+R/2,CY-R); G.DrawLine(P,CX+R,CY-R,CX+R,CY-R/2);
    G.DrawLine(P,CX-R,CY+R,CX-R/2,CY+R); G.DrawLine(P,CX-R,CY+R,CX-R,CY+R/2);
    G.DrawLine(P,CX+R,CY+R,CX+R/2,CY+R); G.DrawLine(P,CX+R,CY+R,CX+R,CY+R/2);
  finally P.Free; end;
  case Kind of
    0: Caption(G,'PHOTO  HDR',Screen.X+12,Screen.Y+44,Screen.Width-24,24,16,$EEFFFFFF);
    1: Caption(G,'AUTO  12M',Screen.X+12,Screen.Y+18,Screen.Width-24,24,16,$EEFFFFFF);
    2: Caption(G,'M  RAW',Screen.X+12,Screen.Y+18,Screen.Width-24,24,16,$EEFFFFFF);
    3: Caption(G,'INSTANT  08',Screen.X+12,Screen.Y+18,Screen.Width-24,24,16,$EEFFFFFF);
  end;
  if (Kind=0) and (Orientation=0) then
  begin
    Ellipse(G,CX-27,Screen.Y+Screen.Height-86,54,54,$DDFFFFFF);
    Ellipse(G,CX-22,Screen.Y+Screen.Height-81,44,44,$FF303840);
    Ellipse(G,CX-19,Screen.Y+Screen.Height-78,38,38,$FFFFFFFF);
  end
  else if Kind=0 then
    Ellipse(G,Screen.X+Screen.Width-82,CY-27,54,54,$EEFFFFFF)
  else
    case Kind of
      1: Caption(G,'AUTO   1/250   F4.0',Screen.X+8,Screen.Y+Screen.Height-28,Screen.Width-16,22,13,$EEFFFFFF);
      2: Caption(G,'AF-S   1/125   F2.8   ISO 100',Screen.X+8,Screen.Y+Screen.Height-28,Screen.Width-16,22,13,$EEFFFFFF);
      3: Caption(G,'FLASH ON   EXP 0',Screen.X+8,Screen.Y+Screen.Height-28,Screen.Width-16,22,13,$EEFFFFFF);
    end;
end;

function CameraBitmap(Phone: TSmartphoneRenderer; Source: TGPBitmap;
  const S, SampleSettings:TPhotoShotSettings; const SamplePose:TPhotoShotState):TGPBitmap;
var G: TGPGraphics; Inner: TGPBitmap; W,H: Integer; Screen: TGPRectF;
begin
  CameraGeometry(S.CameraKind,S.Orientation,W,H,Screen);
  Result:=NewBitmap(W,H); Inner:=nil;
  G:=TGPGraphics.Create(Result);
  try
    G.Clear(0); G.SetSmoothingMode(SmoothingModeAntiAlias);
    Inner:=RenderPhotoShotView(Source,SampleSettings,SamplePose,Round(Screen.Width),Round(Screen.Height));
    if S.CameraKind=0 then
      Phone.Draw(G,Rect(0,0,W,H),S.Orientation,$FF303840,$FF000000,Inner)
    else
    begin
      case S.CameraKind of
        1: begin
          RoundFill(G,2,20,W-4,H-22,32,$FFB9C2CA);
          RoundFill(G,30,5,100,30,8,$FF535B65);
          RoundFill(G,W-110,30,100,H-70,28,$FF3D4650);
        end;
        2: begin
          RoundFill(G,4,52,W-8,H-56,35,$FF252A30);
          RoundFill(G,W/2-90,4,180,75,16,$FF252A30);
          RoundFill(G,W-116,36,106,H-64,28,$FF161A20);
          Ellipse(G,W/2-30,14,60,25,$FF11151A);
        end;
        3: begin
          RoundFill(G,2,2,W-4,H-4,58,$FFF1EBDD);
          RoundFill(G,14,H-124,W-28,110,24,$FFD8D0C1);
          RoundFill(G,W/2-130,H-103,260,12,5,$FF20252B);
          Fill(G,44,62,W-88,7,$FFB6504F);
          Fill(G,44,69,W-88,7,$FFE1BB55);
          Fill(G,44,76,W-88,7,$FF5B9A87);
        end;
      end;
      RoundFill(G,Screen.X-7,Screen.Y-7,Screen.Width+14,Screen.Height+14,12,$FF080B0E);
      G.DrawImage(Inner,Screen);
      if S.CameraKind<>3 then
      begin
        Ellipse(G,W-92,100,58,58,$FF191E25);
        Ellipse(G,W-82,110,38,38,$FF4A555E);
        Caption(G,'OK',W-83,118,40,22,14,$FFFFFFFF);
        Ellipse(G,W-80,200,34,34,$FF8B949C);
        Ellipse(G,W-80,260,34,34,$FF8B949C);
      end;
    end;
    CameraUI(G,Screen,S.CameraKind,S.Orientation);
  finally Inner.Free; G.Free; end;
end;

// 写真はシャッター時の内部トリミングを維持し、背景のぼかし・暗さを焼き込まない。
function PhotoBitmap(Source:TGPBitmap; const S:TPhotoShotSettings;
  const Pose:TPhotoShotState; CanvasW,CanvasH:Integer):TGPBitmap;
var W,H,PW,PH,Border,Bottom:Integer; Screen:TGPRectF; Ratio:Double;
  Photo:TGPBitmap; G:TGPGraphics;
begin
  CameraGeometry(S.CameraKind,S.Orientation,W,H,Screen);
  Ratio:=Min(CanvasW/Screen.Width,CanvasH/Screen.Height);
  PW:=Max(1,Round(Screen.Width*Ratio)); PH:=Max(1,Round(Screen.Height*Ratio));
  Border:=0; Bottom:=0;
  if S.PreviewStyle>0 then begin Border:=Max(8,Round(Min(PW,PH)*0.035)); Bottom:=Border; end;
  if S.PreviewStyle=2 then Bottom:=Border*4;
  Result:=nil; Photo:=nil; G:=nil;
  try
    try
      Photo:=RenderPhotoShotView(Source,S,Pose,PW,PH);
      Result:=NewBitmap(PW+2*Border,PH+Border+Bottom);
      G:=TGPGraphics.Create(Result);
    G.Clear($FFFFFFFF);
    RequireGdi(G.DrawImage(Photo,Border,Border,PW,PH),'Photo content');
    // カメラ別の撮影情報は仮数値。日付は仕様未確定のため追加しない。
    G.TranslateTransform(Border,Border);
    G.ScaleTransform(PW/Screen.Width,PH/Screen.Height);
    CameraUI(G,MakeRect(Single(0),Single(0),Screen.Width,Screen.Height),S.CameraKind,S.Orientation);
    except
      FreeAndNil(G);
      FreeAndNil(Result);
      raise;
    end;
  finally G.Free; Photo.Free; end;
end;

// シャッターは画面中心の演出。入力画像は不変で、再生順のキャッシュを使用しない。
procedure Shutter(G:TGPGraphics; W,H,Kind:Integer; Progress:Double);
var Q,Radius,CX,CY,Angle:Double; B:TGPSolidBrush; Path:TGPGraphicsPath;
  Points:array[0..5] of TGPPointF; I:Integer;
begin
  Q:=Sin(EnsureRange(Progress,0.0,1.0)*Pi);
  if (Kind=0) or (Q<=0) or (Kind=3) then Exit;
  if Kind=1 then begin Fill(G,0,0,W,H,Cardinal(Round(255*Q)) shl 24 or $00FFFFFF); Exit; end;
  if Kind=2 then begin Fill(G,0,0,W,H,Cardinal(Round(255*Q)) shl 24); Exit; end;
  if Kind=6 then
  begin
    Fill(G,0,0,W*Q/2,H,$FF080A0C); Fill(G,W-W*Q/2,0,W*Q/2,H,$FF080A0C); Exit;
  end;
  if Kind=7 then
  begin
    Fill(G,0,0,W,H*Q/2,$FF080A0C); Fill(G,0,H-H*Q/2,W,H*Q/2,$FF080A0C); Exit;
  end;
  if Kind=8 then
  begin
    Q:=Sin(EnsureRange(Progress*2,0.0,1.0)*Pi);
    Fill(G,0,0,W*Q/2,H,$FF080A0C); Fill(G,W-W*Q/2,0,W*Q/2,H,$FF080A0C);
    Q:=Sin(EnsureRange((Progress-0.5)*2,0.0,1.0)*Pi);
    Fill(G,0,0,W,H*Q/2,$FF080A0C); Fill(G,0,H-H*Q/2,W,H*Q/2,$FF080A0C); Exit;
  end;
  CX:=W/2; CY:=H/2;
  Radius:=Sqrt(Sqr(W)+Sqr(H))*0.62*(1-Q);
  Path:=TGPGraphicsPath.Create(FillModeAlternate); B:=TGPSolidBrush.Create($FF101318);
  try
    Path.AddRectangle(MakeRect(0,0,W,H));
    if Kind=4 then Path.AddEllipse(Single(CX-Radius),Single(CY-Radius),Single(2*Radius),Single(2*Radius))
    else
    begin
      for I:=0 to 5 do
      begin Angle:=I*Pi/3+Progress*Pi/3;
        Points[I]:=MakePoint(Single(CX+Cos(Angle)*Radius),Single(CY+Sin(Angle)*Radius)); end;
      Path.AddPolygon(PGPPointF(@Points[0]),Length(Points));
    end;
    G.FillPath(B,Path);
  finally B.Free; Path.Free; end;
  if Kind=9 then Fill(G,0,0,W,H,Cardinal(Round(255*Power(Q,8))) shl 24 or $00FFFFFF);
end;

constructor TPhotoShotRenderer.Create;
var Input:TGdiplusStartupInput;
begin
  inherited Create;
  Input:=Default(TGdiplusStartupInput); Input.GdiplusVersion:=1;
  if GdiplusStartup(FToken,@Input,nil)<>Ok then
    raise Exception.Create('PhotoShot GDI+ initialization failed');
  FPhone:=TSmartphoneRenderer.Create;
end;

destructor TPhotoShotRenderer.Destroy;
begin
  FOutput.Free; FPhone.Free;
  if FToken<>0 then GdiplusShutdown(FToken);
  inherited Destroy;
end;

function TPhotoShotRenderer.Render(Current,Snapshot:TGPBitmap;
  const Settings:TPhotoShotSettings; Frame:Integer;
  CapturedSettings:PPhotoShotSettings):TGPBitmap;
var State,CapturePose:TPhotoShotState; G:TGPGraphics; Camera,Photo,CameraSource:TGPBitmap;
  W,H:Integer; Fit,Shake,ShutterProgress:Double;
  PhotoSettings:TPhotoShotSettings; FrozenCamera:Boolean;
begin
  Result:=nil;
  if (Current=nil) or (Current.GetWidth=0) or (Current.GetHeight=0) then Exit;
  W:=Current.GetWidth; H:=Current.GetHeight;
  if (FOutput=nil) or (Integer(FOutput.GetWidth)<>W) or (Integer(FOutput.GetHeight)<>H) then
  begin FreeAndNil(FOutput); FOutput:=NewBitmap(W,H); end;
  State:=EvaluatePhotoShot(Settings,Frame,W,H);
  // 確定写真は撮影時の全カメラ設定と実姿勢で採取し直す。写真枠と最終配置は現在値。
  PhotoSettings:=Settings;
  if CapturedSettings<>nil then
  begin
    PhotoSettings:=CapturedSettings^;
    PhotoSettings.PreviewStyle:=Settings.PreviewStyle;
  end;
  CapturePose:=EvaluatePhotoShot(PhotoSettings,0,W,H);
  CapturePose:=EvaluatePhotoShot(PhotoSettings,CapturePose.ShutterFrame,W,H);
  // 1 フレームでも視覚ピークを表示する。撮影時刻・段階の長さ自体は変更しない。
  ShutterProgress:=State.Progress;
  if (State.Phase=2) and (Settings.ShutterFrames=1) then ShutterProgress:=0.5;
  G:=TGPGraphics.Create(FOutput); Camera:=nil; Photo:=nil;
  try
    RequireGdi(G.Clear(0),'Output clear'); RequireGdi(G.DrawImage(Current,0,0,W,H),'Background');
  finally G.Free; end;
  Blur(FOutput,Round(EnsureRange(Settings.BackgroundBlur,0.0,100.0)*Min(W,H)/1000));
  G:=TGPGraphics.Create(FOutput);
  try
    G.SetSmoothingMode(SmoothingModeAntiAlias);
    G.SetInterpolationMode(InterpolationModeHighQualityBicubic);
    Fill(G,0,0,W,H,Cardinal(Round(EnsureRange(Settings.BackgroundDark,0.0,100.0)*2.55)) shl 24);
    if State.CameraVisible then
    begin
      CameraSource:=Current;
      FrozenCamera:=(Frame>=State.ShutterFrame) and (Snapshot<>nil);
      if FrozenCamera then CameraSource:=Snapshot;
      // 絞り＋静止画切替だけは、閉じる前半にライブ像を維持し、完全閉鎖時に切り替える。
      // 撮影画像が未取得の場合は常に Current のまま。再生履歴は使用しない。
      if (State.Phase=2) and (Settings.ShutterEffect=10) and (ShutterProgress<0.5) then
      begin CameraSource:=Current; FrozenCamera:=False; end;
      if FrozenCamera then Camera:=CameraBitmap(FPhone,CameraSource,Settings,PhotoSettings,CapturePose)
      else Camera:=CameraBitmap(FPhone,CameraSource,Settings,Settings,State);
      Shake:=0;
      if (State.Phase=2) and (Settings.ShutterEffect=3) then
        if Settings.ShutterFrames=1 then Shake:=Min(W,H)*0.012
        else Shake:=Sin(ShutterProgress*Pi*8)*Sin(ShutterProgress*Pi)*Min(W,H)*0.012;
      Place(G,Camera,W/2+State.CameraX+Shake,H/2+State.CameraY-Shake/2,
        State.CameraScale/100,State.CameraRotation,State.CameraOpacity,State.CameraVerticalScale);
    end;
    if State.PreviewVisible and (Snapshot<>nil) then
    begin
      Photo:=PhotoBitmap(Snapshot,PhotoSettings,CapturePose,W,H);
      Fit:=Min(W/Photo.GetWidth,H/Photo.GetHeight);
      if Settings.PreviewStyle>0 then Fit:=Fit*0.86;
      Place(G,Photo,W/2+State.PreviewX,H/2+State.PreviewY,
        Fit*State.PreviewScale/100,State.PreviewRotation,State.PreviewOpacity,State.PreviewVerticalScale);
    end;
    if State.Phase=2 then
      if (Settings.ShutterFrames=1) and (Settings.ShutterEffect=8) then
        Shutter(G,W,H,Settings.ShutterEffect,0.25)
      else Shutter(G,W,H,Settings.ShutterEffect,ShutterProgress);
  finally Photo.Free; Camera.Free; G.Free; end;
  Result:=FOutput;
end;

end.
