program PhotoShotHostAPITests;
{$APPTYPE CONSOLE}
uses System.SysUtils, AviUtl2FilterTypes, SYNC_PhotoShot_HostAPI;
var E: TPhotoShotEditSection; H: TPhotoShotEditHandle; A: TPhotoShotHostAppTable;
procedure Check(OK: Boolean; const Name: string);
begin if not OK then raise Exception.Create(Name); end;
function Slot(Base: Pointer; Offset: Integer): NativeUInt;
begin Result := PNativeUInt(NativeUInt(Base) + NativeUInt(Offset))^; end;
begin
  try
    Check(SizeOf(Pointer)=8,'Win64 required');
    Check(SizeOf(TEDIT_SECTION)=216,'base edit section size');
    Check(SizeOf(TPhotoShotEditSection)=664,'extended edit prefix size');
    Check(SizeOf(TPhotoShotEditHandle)=112,'edit handle prefix size');
    Check(SizeOf(TPhotoShotHostAppTable)=232,'host app table size');
    Check(SizeOf(TPhotoShotCommonPluginTable)=16,'common table size');
    FillChar(E,SizeOf(E),0); FillChar(H,SizeOf(H),0); FillChar(A,SizeOf(A),0);
    E.FindEffect:=TPhotoShotFindEffect(Pointer(NativeUInt($11223344)));
    E.GetObjectID:=TPhotoShotGetObjectID(Pointer(NativeUInt($22334455)));
    E.GetEffectID:=TPhotoShotGetEffectID(Pointer(NativeUInt($33445566)));
    Check(Slot(@E,400)=$11223344,'find_effect 400');
    Check(Slot(@E,648)=$22334455,'get_object_id 648');
    Check(Slot(@E,656)=$33445566,'get_effect_id 656');
    H.GetEditInfo:=TPhotoShotGetEditInfo(Pointer(NativeUInt($11223344)));
    H.GetEditState:=TPhotoShotGetEditState(Pointer(NativeUInt($22334455)));
    H.RenderingSceneVideo:=TPhotoShotRenderingSceneVideo(Pointer(NativeUInt($33445566)));
    H.WaitRenderingTask:=TPhotoShotWaitRenderingTask(Pointer(NativeUInt($44556677)));
    Check(Slot(@H,16)=$11223344,'get_edit_info 16');
    Check(Slot(@H,56)=$22334455,'get_edit_state 56');
    Check(Slot(@H,88)=$33445566,'rendering_scene_video 88');
    Check(Slot(@H,104)=$44556677,'wait_rendering_task 104');
    A.RegisterFilterPlugin:=TPhotoShotRegisterFilterPlugin(Pointer(NativeUInt($11223344)));
    A.CreateEditHandle:=TPhotoShotCreateEditHandle(Pointer(NativeUInt($22334455)));
    A.RegisterEventListener:=TPhotoShotRegisterEventListener(Pointer(NativeUInt($33445566)));
    Check(Slot(@A,24)=$11223344,'register_filter_plugin 24');
    Check(Slot(@A,64)=$22334455,'create_edit_handle 64');
    Check(Slot(@A,224)=$33445566,'register_event_listener 224');
    Writeln('PASS: 6 sizes and 10 function offsets; no SDK callbacks invoked');
  except on X:Exception do begin Writeln(X.Message); Halt(1); end; end;
end.
