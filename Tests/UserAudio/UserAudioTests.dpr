program UserAudioTests;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Math, MP3Decoder, SYNC_PhotoShot_MP3;
var
  Native: TDecodedAudio;
  Audio: TPhotoShotPCM;
  I, FirstFrame, LastFrame: Integer;
  Peak, Sum: Double;
begin
  try
    if ParamCount <> 1 then raise Exception.Create('Expected MP3 filename');
    Native := DecodeMP3(ParamStr(1));
    Audio := DecodePhotoShotMP3(ParamStr(1));
    if (Audio.FrameCount=0) or (Audio.SampleRate<>44100) or
      (Audio.Channels<>2) then raise Exception.Create('Invalid output format');
    Peak:=0; Sum:=0; FirstFrame:=-1; LastFrame:=-1;
    for I:=0 to High(Audio.Samples) do
    begin
      if IsNan(Audio.Samples[I]) or IsInfinite(Audio.Samples[I]) or
        (Audio.Samples[I] < -1) or (Audio.Samples[I]>=1) then
        raise Exception.Create('Invalid float sample');
      Peak:=Max(Peak,Abs(Audio.Samples[I]));
      Sum:=Sum+Sqr(Audio.Samples[I]);
      if Abs(Audio.Samples[I])>1/32768 then
      begin
        if FirstFrame<0 then FirstFrame:=I div 2;
        LastFrame:=I div 2;
      end;
    end;
    if Peak=0 then raise Exception.Create('Silent audio');
    Writeln('PASS');
    Writeln('native_rate=',Native.SampleRate,' native_channels=',Native.Channels,
      ' native_frames=',Native.FrameCount,' gapless=',Native.GaplessApplied);
    Writeln('output_rate=',Audio.SampleRate,' output_channels=',Audio.Channels,
      ' output_frames=',Audio.FrameCount);
    Writeln('duration_seconds=',FormatFloat('0.000000',Audio.FrameCount/44100),
      ' peak=',FormatFloat('0.000000',Peak),
      ' rms=',FormatFloat('0.000000',Sqrt(Sum/Length(Audio.Samples))));
    Writeln('leading_seconds_above_pcm16_1=',FormatFloat('0.000000',FirstFrame/44100),
      ' last_nonzero_seconds=',FormatFloat('0.000000',LastFrame/44100));
  except on E:Exception do begin Writeln('FAIL: ',E.ClassName,': ',E.Message);Halt(1);end;end;
end.
