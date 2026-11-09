unit SYNC_PhotoShot_Renderer;

// カメラのライブビューと撮影演出を現在入力だけから合成する。
// 撮影結果の保持・写真表示・ファイル出力は行わない。
interface

uses
  Winapi.Windows, Winapi.GDIPAPI, Winapi.GDIPOBJ,
  SYNC_SmartphoneRenderer, SYNC_PhotoShot_Timeline;

type
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
    // Current は呼出側所有の現在入力。保存せず、この呼出し中だけ借用する。
    // 戻り値は本インスタンス所有 PARGB 画像。次の Render または Destroy まで有効。
    // 入力 nil は nil。プレビューはカメラ内のライブビューを指し、撮影写真は扱わない。
    function Render(Current:TGPBitmap; const Settings:TPhotoShotSettings;
      Frame:Integer):TGPBitmap;
  end;

// カメラ画面の画面上領域を現在入力から採取する。ライブビュー用でUIを含まない。
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
  if (Image=nil) or (Scale<=1E-6) or (Opacity<=0) then Exit;
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

procedure CameraGeometry(Kind,Orientation,CanvasW,CanvasH:Integer; out W,H:Integer; out Screen:TGPRectF);
begin
  if Kind=0 then
  begin
    SmartphoneSize(Orientation,W,H);
    // 撮影領域を広く取り、長辺の両端だけを細い操作帯として残す。
    if Orientation=1 then
      Screen:=MakeRect(Single(104),Single(18),Single(612),Single(384))
    else
      Screen:=MakeRect(Single(14),Single(103),Single(392),Single(614));
  end
  else
  begin
    // 非スマホは筐体なし。倍率100の撮影範囲は映像canvas全体。
    W:=Max(1,CanvasW); H:=Max(1,CanvasH);
    Screen:=MakeRect(Single(0),Single(0),Single(W),Single(H));
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
    // サブピクセル未満の倍率で逆行列を巨大化させない。不可視域は黒／配置なし。
    if (Source=nil) or (Scale<=1E-6) or (Pose.CameraVerticalScale<=1E-6) then Exit;
    CameraGeometry(S.CameraKind,S.Orientation,Source.GetWidth,Source.GetHeight,BodyW,BodyH,Screen);
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
  // 内部ぼかしはライブビューへ適用する。背景のぼかし・暗さとは独立させる。
  Blur(Result,Round(EnsureRange(S.InnerBlur,0.0,100.0)*Min(W,H)/1000));
  except
    Result.Free;
    raise;
  end;
end;
procedure CameraUI(G: TGPGraphics; const Screen: TGPRectF; Kind,Orientation: Integer);
var P: TGPPen; CX,CY,R,BX,BY: Single;
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
    0:
      if Orientation=1 then
      begin
        Caption(G,'PHOTO',44,134,56,24,11,$EEFFFFFF);
        Caption(G,'HDR',44,164,56,24,11,$EEFFFFFF);
      end
      else Caption(G,'PHOTO  HDR',Screen.X+12,60,Screen.Width-24,24,16,$EEFFFFFF);
    1: Caption(G,'AUTO  12M',Screen.X+12,Screen.Y+18,Screen.Width-24,24,16,$EEFFFFFF);
    2: Caption(G,'M  RAW',Screen.X+12,Screen.Y+18,Screen.Width-24,24,16,$EEFFFFFF);
    3: Caption(G,'INSTANT  08',Screen.X+12,Screen.Y+18,Screen.Width-24,24,16,$EEFFFFFF);
  end;
  if Kind=0 then
  begin
    if Orientation=1 then
    begin BX:=(Screen.X+Screen.Width+806)/2; BY:=210; end
    else begin BX:=210; BY:=(Screen.Y+Screen.Height+802)/2; end;
    Ellipse(G,BX-27,BY-27,54,54,$DDFFFFFF);
    Ellipse(G,BX-22,BY-22,44,44,$FF303840);
    Ellipse(G,BX-19,BY-19,38,38,$FFFFFFFF);
  end
  else
    case Kind of
      1: Caption(G,'AUTO   1/250   F4.0',Screen.X+8,Screen.Y+Screen.Height-28,Screen.Width-16,22,13,$EEFFFFFF);
      2: Caption(G,'AF-S   1/125   F2.8   ISO 100',Screen.X+8,Screen.Y+Screen.Height-28,Screen.Width-16,22,13,$EEFFFFFF);
      3: Caption(G,'FLASH ON   EXP 0',Screen.X+8,Screen.Y+Screen.Height-28,Screen.Width-16,22,13,$EEFFFFFF);
    end;
end;

// 撮影情報は演出用の仮表示であり、EXIF・実カメラ設定の読取結果ではない。
// 枠だけで種別を区別し、筐体や写真枠は描かない。基準640x360をcanvasへ配置する。
procedure FinderUI(G:TGPGraphics; W,H,Kind:Integer);
var Saved:GraphicsState; P:TGPPen; I:Integer; A:Single;
begin
  Saved:=G.Save;
  try
    G.ScaleTransform(W/640,H/360);
    Fill(G,12,12,616,28,$66000000);
    Fill(G,12,320,616,28,$66000000);
    P:=TGPPen.Create($CCFFFFFF,1.5);
    try
      // 外周は短い四隅のガイド。中央は広く空け、撮影対象を隠さない。
      G.DrawLine(P,16,55,16,16); G.DrawLine(P,16,16,55,16);
      G.DrawLine(P,585,16,624,16); G.DrawLine(P,624,16,624,55);
      G.DrawLine(P,16,305,16,344); G.DrawLine(P,16,344,55,344);
      G.DrawLine(P,585,344,624,344); G.DrawLine(P,624,344,624,305);
      G.DrawLine(P,280,145,280,165); G.DrawLine(P,280,145,300,145);
      G.DrawLine(P,340,145,360,145); G.DrawLine(P,360,145,360,165);
      G.DrawLine(P,280,195,280,215); G.DrawLine(P,280,215,300,215);
      G.DrawLine(P,340,215,360,215); G.DrawLine(P,360,195,360,215);
      if Kind=2 then
      begin
        // 一眼レフは多点AF・水平水準・露出目盛りを追加。
        for I:=0 to 2 do
        begin
          A:=220+100*I;
          G.DrawRectangle(P,A-7,103,14,14); G.DrawRectangle(P,A-7,243,14,14);
        end;
        G.DrawLine(P,250,286,390,286);
        for I:=0 to 8 do G.DrawLine(P,256+16*I,282,256+16*I,290);
        G.DrawLine(P,320,278,320,294);
        Caption(G,'-2      -1       0       +1      +2',230,295,180,16,11,$FFFFFFFF);
      end
      else if Kind=3 then
      begin
        // インスタントは光学ファインダー風の中心印と近距離補正ガイド。
        G.DrawLine(P,314,180,326,180); G.DrawLine(P,320,174,320,186);
        G.DrawLine(P,72,72,568,72);
        Caption(G,'NEAR',72,76,56,18,11,$EEFFFFFF);
      end;
    finally P.Free; end;
    case Kind of
      2:
      begin
        Caption(G,'M   RAW+JPG     AF-S',24,15,260,22,15,$FFFFFFFF);
        Caption(G,'[999]    BAT  87%',420,15,192,22,14,$FFFFFFFF);
        Caption(G,'1/125     F2.8     ISO 100     WB 5500K',26,322,500,22,15,$FFFFFFFF);
        Caption(G,'FX',554,322,60,22,14,$FFFFFFFF);
      end;
      3:
      begin
        Caption(G,'INSTANT',24,15,140,22,16,$FFFBE6B4);
        Caption(G,'08 LEFT',480,15,132,22,16,$FFFBE6B4);
        Caption(G,'FLASH ON      EXP 0',32,322,300,22,15,$FFFFFFFF);
        Caption(G,'AUTO',510,322,100,22,14,$FFFFFFFF);
      end;
    else
      begin
        Caption(G,'AUTO',24,15,100,22,16,$FFFFFFFF);
        Caption(G,'12M    [128]',448,15,164,22,14,$FFFFFFFF);
        Caption(G,'1/250      F4.0',32,322,220,22,15,$FFFFFFFF);
        Caption(G,'AF',544,322,64,22,14,$FFFFFFFF);
      end;
    end;
  finally G.Restore(Saved); end;
end;

procedure DrawCamera(G:TGPGraphics; Phone:TSmartphoneRenderer; Source:TGPBitmap;
  const S:TPhotoShotSettings; const Pose:TPhotoShotState);
var Inner:TGPBitmap; W,H,PhoneW,PhoneH,Direction:Integer; Screen:TGPRectF;
  Saved:GraphicsState; InsetX,InsetY,ScreenW,ScreenH:Double;
begin
  CameraGeometry(S.CameraKind,S.Orientation,Source.GetWidth,Source.GetHeight,W,H,Screen);
  Inner:=nil;
  try
    G.SetSmoothingMode(SmoothingModeAntiAlias);
    Inner:=RenderPhotoShotView(Source,S,Pose,Round(Screen.Width),Round(Screen.Height));
    if S.CameraKind=0 then
    begin
      // スマホの筐体・画面・既存UIは従来の描画順序と値を厳密に維持する。
      Phone.Draw(G,Rect(0,0,W,H),S.Orientation,S.CameraColor,$FF080A0C,Inner,@Screen);
      CameraUI(G,Screen,S.CameraKind,S.Orientation);
    end
    else
    begin
      // 非スマホもスマホの角丸外枠を流用し、色指定を共通化する。
      // canvas全体の撮影像を共通枠内に表示する。カメラ筐体固有形状は作らない。
      if W>H then Direction:=1 else Direction:=0;
      Phone.Draw(G,Rect(0,0,W,H),Direction,S.CameraColor,$FF000000,Inner);
      SmartphoneSize(Direction,PhoneW,PhoneH);
      InsetX:=W*14/PhoneW; InsetY:=H*18/PhoneH;
      ScreenW:=W*(PhoneW-28)/PhoneW; ScreenH:=H*(PhoneH-36)/PhoneH;
      Saved:=G.Save;
      try
        G.TranslateTransform(InsetX,InsetY);
        FinderUI(G,Round(ScreenW),Round(ScreenH),S.CameraKind);
      finally G.Restore(Saved); end;
    end;
  finally Inner.Free; end;
end;
// シャッターは画面中心の演出。入力画像は不変で、再生順のキャッシュを使用しない。
// 不透明度100では出力へ直接描く。半透明は枠/UI一括合成を守る旧経路。
function CameraBitmap(Phone:TSmartphoneRenderer; Source:TGPBitmap;
  const S:TPhotoShotSettings; const Pose:TPhotoShotState):TGPBitmap;
var G:TGPGraphics; W,H:Integer; Screen:TGPRectF;
begin
  CameraGeometry(S.CameraKind,S.Orientation,Source.GetWidth,Source.GetHeight,W,H,Screen);
  Result:=NewBitmap(W,H);
  try
    G:=TGPGraphics.Create(Result);
    try
      RequireGdi(G.Clear(0),'Camera clear');
      DrawCamera(G,Phone,Source,S,Pose);
    finally G.Free; end;
  except
    Result.Free;
    raise;
  end;
end;

procedure DrawCameraDirect(G:TGPGraphics; Phone:TSmartphoneRenderer; Source:TGPBitmap;
  const S:TPhotoShotSettings; const Pose:TPhotoShotState; Shake:Double);
var Saved:GraphicsState; W,H:Integer; Screen:TGPRectF; Scale:Double;
begin
  Scale:=Pose.CameraScale/100;
  if (Scale<=1E-6) or (Pose.CameraOpacity<=0) then Exit;
  CameraGeometry(S.CameraKind,S.Orientation,Source.GetWidth,Source.GetHeight,W,H,Screen);
  Saved:=G.Save;
  try
    G.TranslateTransform(Source.GetWidth/2+Pose.CameraX+Shake,
      Source.GetHeight/2+Pose.CameraY-Shake/2);
    G.RotateTransform(Pose.CameraRotation);
    G.ScaleTransform(Scale,Scale*EnsureRange(Pose.CameraVerticalScale,0.01,1.0));
    G.TranslateTransform(-W/2,-H/2);
    // 旧中間画像の境界と同じ範囲にUIも制限する。
    G.SetClip(MakeRect(0,0,W,H),CombineModeIntersect);
    DrawCamera(G,Phone,Source,S,Pose);
  finally G.Restore(Saved); end;
end;

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

function TPhotoShotRenderer.Render(Current:TGPBitmap;
  const Settings:TPhotoShotSettings; Frame:Integer):TGPBitmap;
var State:TPhotoShotState; G:TGPGraphics; Camera:TGPBitmap;
  W,H:Integer; Shake,ShutterProgress:Double;
begin
  Result:=nil;
  if (Current=nil) or (Current.GetWidth=0) or (Current.GetHeight=0) then Exit;
  W:=Current.GetWidth; H:=Current.GetHeight;
  if (FOutput=nil) or (Integer(FOutput.GetWidth)<>W) or (Integer(FOutput.GetHeight)<>H) then
  begin FreeAndNil(FOutput); FOutput:=NewBitmap(W,H); end;
  State:=EvaluatePhotoShot(Settings,Frame,W,H);
  // 1 フレームでも視覚ピークを表示する。撮影時刻・段階の長さ自体は変更しない。
  ShutterProgress:=State.Progress;
  if (State.Phase=2) and (Settings.ShutterFrames=1) then ShutterProgress:=0.5;
  G:=TGPGraphics.Create(FOutput); Camera:=nil;
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
      // シャッター後も、カメラが表示されている間は常に現在入力をライブ表示する。
      Shake:=0;
      if (State.Phase=2) and (Settings.ShutterEffect=3) then
        if Settings.ShutterFrames=1 then Shake:=Min(W,H)*0.012
        else Shake:=Sin(ShutterProgress*Pi*8)*Sin(ShutterProgress*Pi)*Min(W,H)*0.012;
      if (State.CameraScale/100>1E-6) and (State.CameraOpacity>0) then
        if State.CameraOpacity>=100 then
          DrawCameraDirect(G,FPhone,Current,Settings,State,Shake)
        else
        begin
          Camera:=CameraBitmap(FPhone,Current,Settings,State);
          Place(G,Camera,W/2+State.CameraX+Shake,H/2+State.CameraY-Shake/2,
            State.CameraScale/100,State.CameraRotation,State.CameraOpacity,State.CameraVerticalScale);
        end;
    end;
    if State.Phase=2 then
      if (Settings.ShutterFrames=1) and (Settings.ShutterEffect=8) then
        Shutter(G,W,H,Settings.ShutterEffect,0.25)
      else Shutter(G,W,H,Settings.ShutterEffect,ShutterProgress);
  finally Camera.Free; G.Free; end;
  Result:=FOutput;
end;

end.
