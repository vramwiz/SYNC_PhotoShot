program MP3DecoderTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.Math,
  MP3Decoder, SYNC_PhotoShot_MP3;

var
  Audio: TDecodedAudio;
  FloatAudio: TPhotoShotPCM;
  I: Integer;
  Peak: Single;
  Stream: TFileStream;
begin
  try
    if ParamCount <> 1 then raise Exception.Create('Expected one MP3 file');
    Audio := DecodeMP3(ParamStr(1));
    if (Audio.FrameCount <= 0) or (Audio.Channels < 1) or (Audio.Channels > 2) then
      raise Exception.Create('Invalid native PCM');
    SaveAudioWAV(ParamStr(1) + '.decoded.wav', Audio);
    FloatAudio := DecodePhotoShotMP3(ParamStr(1));
    if (FloatAudio.SampleRate <> 44100) or (FloatAudio.Channels <> 2) or
      (FloatAudio.FrameCount <= 0) then raise Exception.Create('Wrong float PCM contract');
    Peak := 0;
    for I := 0 to High(FloatAudio.Samples) do
    begin
      if IsNan(FloatAudio.Samples[I]) or IsInfinite(FloatAudio.Samples[I]) or
        (FloatAudio.Samples[I] < -1) or (FloatAudio.Samples[I] >= 1) then
        raise Exception.Create('Invalid float sample');
      Peak := Max(Peak, Abs(FloatAudio.Samples[I]));
    end;
    Stream := TFileStream.Create(ParamStr(1) + '.float.pcm', fmCreate);
    try
      Stream.WriteBuffer(FloatAudio.Samples[0], Length(FloatAudio.Samples) * SizeOf(Single));
    finally
      Stream.Free;
    end;
    Writeln('PASS rate=', Audio.SampleRate, ' channels=', Audio.Channels,
      ' native_frames=', Audio.FrameCount, ' float_frames=', FloatAudio.FrameCount,
      ' peak=', FormatFloat('0.000000', Peak), ' gapless=', Audio.GaplessApplied);
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
