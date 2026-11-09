unit MP3Decoder;

interface
uses System.SysUtils, System.Classes;
const MP3_DECODER_VERSION = 'pascal-minimp3-2';
  MP3_MAX_PCM_BYTES = 512 * Int64(1024) * 1024;
type
  EMP3DecodeError = class(Exception);
  TDecodedAudio = record
    SampleRate, Channels: Integer;
    PCM: TBytes; // signed PCM16 little endian, interleaved
    DecodedFrames: Integer;
    EncoderDelay, EncoderPadding: Integer;
    GaplessApplied: Boolean;
    DeclaredFrames, DeclaredBytes: Cardinal;
    FrameCountMismatch: Boolean; // accepted when parsed span and Xing byte size agree
    function FrameCount: Int64;
  end;
function DecodeMP3(const FileName: string; const Cancel: TFunc<Boolean> = nil): TDecodedAudio;
function ToStereo44100(const Audio: TDecodedAudio; const Cancel: TFunc<Boolean> = nil): TBytes;
procedure SaveAudioWAV(const FileName: string; const Audio: TDecodedAudio);
implementation
uses System.Math, System.IOUtils, Winapi.Windows, MP3Types, MP3BitStream, MP3Frame, MP3Layer3;

procedure CheckCancel(const Cancel: TFunc<Boolean>);
begin if Assigned(Cancel) and Cancel() then Abort; end;
function TDecodedAudio.FrameCount: Int64;
begin if Channels > 0 then Result := Length(PCM) div (Channels*2) else Result := 0; end;
function ReadBE32(const B: TBytes; P: Integer): Cardinal;
begin Result := Cardinal(B[P]) shl 24 or Cardinal(B[P+1]) shl 16 or Cardinal(B[P+2]) shl 8 or B[P+3]; end;
function IsTag(const B: TBytes; P: Integer; const S: AnsiString): Boolean;
var I: Integer;
begin Result:=False; if (P<0) or (P+Length(S)>Length(B)) then Exit;
  for I:=1 to Length(S) do if B[P+I-1]<>Ord(S[I]) then Exit; Result:=True; end;
function DecodeMP3(const FileName: string; const Cancel: TFunc<Boolean>): TDecodedAudio;
var Input: TFileStream; Output: TMemoryStream; Decoder: TMP3Layer3Decoder;
  H, FirstHeader: TMP3FrameHeader; SI: TMP3SideInfo; Bits: TMP3BitStream;
  FB, Side, Main, Reservoir, Tag: TBytes; L,R: TArray<Single>;
  ResLen, SideSize, CRCSize, Payload, I,J,Start,Flags,EndSkip,Keep,N: Integer;
  First,InfoFrame: Boolean; FrameStart,AudioEnd,FirstFrameStart,ParsedEnd: Int64; Sample: SmallInt;
  ExpectedFrames: Cardinal; HaveGapless: Boolean;
begin
  Result:=Default(TDecodedAudio); Result.EncoderDelay:=-1; Result.EncoderPadding:=-1;
  CheckCancel(Cancel);
  Input:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  Output:=nil; Decoder:=nil;
  try
    if (Input.Size<4) or (Input.Size>MP3_MAX_PCM_BYTES) then raise EMP3DecodeError.Create('MP3 input is empty, too short, or exceeds the 512 MiB limit.');
    Output:=TMemoryStream.Create; Decoder:=TMP3Layer3Decoder.Create;
    SetLength(Reservoir,4096); ResLen:=0; First:=True; HaveGapless:=False; ExpectedFrames:=0;
    AudioEnd:=Input.Size; FirstFrameStart:=0; ParsedEnd:=0;
    // ID3v1 is trailing metadata, not MPEG data.
    if AudioEnd>=128 then begin Input.Position:=AudioEnd-128; SetLength(Tag,3); Input.ReadBuffer(Tag[0],3);
      if IsTag(Tag,0,'TAG') then Dec(AudioEnd,128); end;
    Input.Position:=0;
    // Skip leading ID3v2 tags with validated syncsafe size and optional v2.4 footer.
    while Input.Position+10<=AudioEnd do begin
      FrameStart:=Input.Position; SetLength(Tag,10); Input.ReadBuffer(Tag[0],10);
      if not IsTag(Tag,0,'ID3') then begin Input.Position:=FrameStart; Break; end;
      if (Tag[3]<2) or (Tag[3]>4) or ((Tag[6] or Tag[7] or Tag[8] or Tag[9]) and $80<>0) then
        raise EMP3DecodeError.Create('Invalid ID3v2 header.');
      N:=Tag[6] shl 21 or Tag[7] shl 14 or Tag[8] shl 7 or Tag[9];
      if (Tag[3]=4) and (Tag[5] and $10<>0) then Inc(N,10);
      if Input.Position+N>AudioEnd then raise EMP3DecodeError.Create('Truncated ID3v2 tag.');
      Input.Seek(N,soCurrent);
    end;
    while Input.Position+4<=AudioEnd do begin
      CheckCancel(Cancel); FrameStart:=Input.Position;
      if not TMP3FrameParser.ParseHeader(Input,H) then Break;
      if Input.Position<>FrameStart+4 then begin
        if not First then raise EMP3DecodeError.Create('Unexpected bytes between MPEG frames.');
        FrameStart:=Input.Position-4;
      end;
      if FrameStart+H.FrameSize>AudioEnd then raise EMP3DecodeError.Create('Truncated MPEG frame.');
      if First then begin Result.SampleRate:=H.SampleRate; Result.Channels:=H.Channels; FirstHeader:=H; FirstFrameStart:=FrameStart; end
      else if (H.SampleRate<>FirstHeader.SampleRate) or (H.Channels<>FirstHeader.Channels) then
        raise EMP3DecodeError.Create('Changing sample rate or channel count is not supported.');
      SetLength(FB,H.FrameSize-4); Input.ReadBuffer(FB[0],Length(FB)); ParsedEnd:=Input.Position;
      CRCSize:=0; if HDR_IS_CRC(H.hdr) then CRCSize:=2;
      SideSize:=TMP3FrameParser.SideInfoSize(H); Payload:=Length(FB)-CRCSize-SideSize;
      if Payload<0 then raise EMP3DecodeError.Create('Invalid MPEG frame size.');
      InfoFrame:=False;
      if First then begin
        J:=CRCSize+SideSize;
        if IsTag(FB,J,'Xing') or IsTag(FB,J,'Info') then begin
          InfoFrame:=True;
          if J+8>Length(FB) then raise EMP3DecodeError.Create('Truncated Xing header.');
          Flags:=ReadBE32(FB,J+4); Inc(J,8);
          if Flags and 1<>0 then begin if J+4>Length(FB) then raise EMP3DecodeError.Create('Truncated Xing frames.'); ExpectedFrames:=ReadBE32(FB,J); Inc(J,4); end;
          if Flags and 2<>0 then begin
            if J+4>Length(FB) then raise EMP3DecodeError.Create('Truncated Xing byte size.');
            Result.DeclaredBytes:=ReadBE32(FB,J); Inc(J,4);
          end;
          if Flags and 4<>0 then Inc(J,100); if Flags and 8<>0 then Inc(J,4);
          if (J+24<=Length(FB)) and (IsTag(FB,J,'LAME') or IsTag(FB,J,'Lavc') or IsTag(FB,J,'Lavf')) then begin
            Result.EncoderDelay:=FB[J+21] shl 4 or (FB[J+22] shr 4);
            Result.EncoderPadding:=(FB[J+22] and 15) shl 8 or FB[J+23];
            HaveGapless:=(Result.EncoderDelay<4095) and (Result.EncoderPadding<4095);
          end;
        end;
        First:=False;
      end;
      if InfoFrame then Continue;
      Side:=Copy(FB,CRCSize,SideSize); Bits:=TMP3BitStream.Create(Side);
      try if not TMP3FrameParser.ParseSideInfo(Bits,H,SI) then raise EMP3DecodeError.Create('Invalid MPEG side information.'); finally Bits.Free; end;
      if SI.MainDataBegin>ResLen then raise EMP3DecodeError.Create('Missing MP3 bit reservoir data.');
      SetLength(Main,SI.MainDataBegin+Payload);
      if SI.MainDataBegin>0 then Move(Reservoir[ResLen-SI.MainDataBegin],Main[0],SI.MainDataBegin);
      if Payload>0 then Move(FB[CRCSize+SideSize],Main[SI.MainDataBegin],Payload);
      Decoder.DecodeFrame(H,SI,Main,0,L,R);
      if Output.Size+Int64(Length(L))*Result.Channels*2>MP3_MAX_PCM_BYTES then raise EMP3DecodeError.Create('Decoded PCM exceeds 512 MiB limit.');
      for I:=0 to High(L) do begin
        if IsNan(L[I]) or IsInfinite(L[I]) or IsNan(R[I]) or IsInfinite(R[I]) then raise EMP3DecodeError.Create('Non-finite decoded sample.');
        Sample:=EnsureRange(Round(L[I]*32768),-32768,32767); Output.WriteBuffer(Sample,2);
        if Result.Channels=2 then begin Sample:=EnsureRange(Round(R[I]*32768),-32768,32767); Output.WriteBuffer(Sample,2); end;
      end;
      Inc(Result.DecodedFrames);
      Keep:=Min(4096-Payload,ResLen); if Keep<0 then raise EMP3DecodeError.Create('MPEG payload exceeds reservoir.');
      if Keep>0 then Move(Reservoir[ResLen-Keep],Reservoir[0],Keep);
      if Payload>0 then Move(FB[CRCSize+SideSize],Reservoir[Keep],Payload); ResLen:=Keep+Payload;
    end;
    if (Result.DecodedFrames=0) or (Output.Size=0) then raise EMP3DecodeError.Create('No decodable MPEG Layer III audio.');
    Result.DeclaredFrames:=ExpectedFrames;
    Result.FrameCountMismatch:=(ExpectedFrames>0) and (ExpectedFrames<>Cardinal(Result.DecodedFrames));
    // Some encoders (FFmpeg mp3_mf) put multiple MPEG frames in one packet.
    // Their muxer counts packets in Xing. This is metadata consistency,
    // not an authenticity guarantee: compare against actual parsed frames.
    if (Result.DeclaredBytes>0) and ((Int64(Result.DeclaredBytes)<>ParsedEnd-FirstFrameStart) or
      (ParsedEnd<>AudioEnd)) then raise EMP3DecodeError.Create('Xing byte size does not match parsed MPEG frames.');
    if Result.FrameCountMismatch and (Result.DeclaredBytes=0) then
      raise EMP3DecodeError.CreateFmt('Incomplete MP3 or inconsistent Xing metadata: declared %d frames; found %d.',[ExpectedFrames,Result.DecodedFrames]);
    Start:=0; EndSkip:=0;
    if HaveGapless then begin Start:=Result.EncoderDelay+529; EndSkip:=Max(0,Result.EncoderPadding-529); Result.GaplessApplied:=True; end;
    N:=Output.Size div (Result.Channels*2);
    if Start+EndSkip>=N then raise EMP3DecodeError.Create('Invalid gapless sample counts.');
    N:=(N-Start-EndSkip)*Result.Channels*2; SetLength(Result.PCM,N);
    Output.Position:=Int64(Start)*Result.Channels*2; Output.ReadBuffer(Result.PCM[0],N);
    CheckCancel(Cancel);
  finally Decoder.Free; Output.Free; Input.Free; end;
end;

function ToStereo44100(const Audio: TDecodedAudio; const Cancel: TFunc<Boolean>): TBytes;
const Radius=32;
var OutCount,InCount,I,K,LeftIndex,C,Index,Phase,Phases,Divisor,A,B,T: Integer;
  PositionNumerator: Int64; X,Cutoff,Weight,WeightSum,Sum,Value: Double;
  Sample: SmallInt; Coeff:TArray<TArray<Double>>;
  function InputSample(Frame,Channel: Integer): SmallInt;
  begin Frame:=EnsureRange(Frame,0,InCount-1); if Audio.Channels=1 then Channel:=0;
    Move(Audio.PCM[(Frame*Audio.Channels+Channel)*2],Result,2); end;
begin
  Result:=nil; InCount:=Audio.FrameCount;
  if (InCount=0) or (Audio.SampleRate<=0) or not (Audio.Channels in [1,2]) then raise EMP3DecodeError.Create('Invalid PCM format.');
  CheckCancel(Cancel);
  if (Audio.SampleRate=44100) and (Audio.Channels=2) then begin Result:=Copy(Audio.PCM); Exit; end;
  OutCount:=Ceil(Int64(InCount)*44100/Audio.SampleRate);
  if Int64(OutCount)*4>MP3_MAX_PCM_BYTES then raise EMP3DecodeError.Create('Converted PCM exceeds 512 MiB limit.');
  SetLength(Result,OutCount*4);
  // Rational polyphase table: compute trig coefficients once, not per sample.
  A:=Audio.SampleRate; B:=44100;
  while B<>0 do begin T:=A mod B; A:=B; B:=T; end;
  Divisor:=A; Phases:=44100 div Divisor;
  if Audio.SampleRate<>44100 then begin
    Cutoff:=Min(1.0,44100.0/Audio.SampleRate)*0.95; SetLength(Coeff,Phases);
    for Phase:=0 to Phases-1 do begin
      SetLength(Coeff[Phase],Radius*2); WeightSum:=0;
      for K:=-Radius+1 to Radius do begin
        X:=K-Phase/Phases; Weight:=0;
        if Abs(X)<Radius then begin
          if Abs(X)<1E-12 then Weight:=Cutoff else Weight:=Sin(Pi*X*Cutoff)/(Pi*X);
          Weight:=Weight*(0.5+0.5*Cos(Pi*X/Radius));
        end;
        Coeff[Phase][K+Radius-1]:=Weight; WeightSum:=WeightSum+Weight;
      end;
      for K:=0 to Radius*2-1 do Coeff[Phase][K]:=Coeff[Phase][K]/WeightSum;
    end;
  end;
  for I:=0 to OutCount-1 do begin
    if I and 1023=0 then CheckCancel(Cancel);
    PositionNumerator:=Int64(I)*Audio.SampleRate;
    LeftIndex:=PositionNumerator div 44100; Phase:=(PositionNumerator mod 44100) div Divisor;
    for C:=0 to Audio.Channels-1 do begin
      if Audio.SampleRate=44100 then Value:=InputSample(I,C)
      else begin
        Sum:=0;
        for K:=-Radius+1 to Radius do begin
          Index:=LeftIndex+K; Sum:=Sum+InputSample(Index,C)*Coeff[Phase][K+Radius-1];
        end;
        Value:=Sum;
      end;
      // FFmpeg's default mono-center to stereo mapping applies -3.0103 dB.
      if Audio.Channels=1 then Value:=Value*Sqrt(0.5);
      Sample:=EnsureRange(Round(Value),-32768,32767);
      Move(Sample,Result[(I*2+C)*2],2);
      if Audio.Channels=1 then Move(Sample,Result[(I*2+1)*2],2);
    end;
  end;
end;
procedure SaveAudioWAV(const FileName: string; const Audio: TDecodedAudio);
var Stream:THandleStream; H:THandle;
  procedure Tag(const S:AnsiString); begin Stream.WriteBuffer(S[1],4); end;
  procedure U32(V:Cardinal); begin Stream.WriteBuffer(V,4); end;
  procedure U16(V:Word); begin Stream.WriteBuffer(V,2); end;
begin
  if (Audio.Channels<1) or (Audio.Channels>2) or (Audio.SampleRate<=0) or
    (Length(Audio.PCM)=0) or (Length(Audio.PCM) mod (Audio.Channels*2)<>0) then raise EMP3DecodeError.Create('Invalid output PCM.');
  // CREATE_NEW guarantees existing source or output files cannot be overwritten.
  H:=CreateFile(PChar(FileName),GENERIC_WRITE,0,nil,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,0);
  if H=INVALID_HANDLE_VALUE then RaiseLastOSError;
  Stream:=THandleStream.Create(H);
  try
    Tag('RIFF'); U32(36+Length(Audio.PCM)); Tag('WAVE'); Tag('fmt '); U32(16); U16(1);
    U16(Audio.Channels); U32(Audio.SampleRate); U32(Audio.SampleRate*Audio.Channels*2); U16(Audio.Channels*2); U16(16);
    Tag('data'); U32(Length(Audio.PCM)); Stream.WriteBuffer(Audio.PCM[0],Length(Audio.PCM));
  finally Stream.Free; CloseHandle(H); end;
end;
end.
