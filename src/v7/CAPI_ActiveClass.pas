unit CAPI_ActiveClass;

{$inline on}

interface

uses
    CAPI_Utils;

procedure ActiveClass_Get_AllNames(var ResultPtr: PPAnsiChar; ResultCount: PInteger); CDECL;
procedure ActiveClass_Get_AllNames_GR(); CDECL;
function ActiveClass_Get_First(): Integer; CDECL;
function ActiveClass_Get_Next(): Integer; CDECL;
function ActiveClass_Get_Name(): PAnsiChar; CDECL;
procedure ActiveClass_Set_Name(const Value: PAnsiChar); CDECL;
function ActiveClass_Get_NumElements(): Integer; CDECL;
function ActiveClass_Get_ActiveClassName(): PAnsiChar; CDECL;
function ActiveClass_Get_Count(): Integer; CDECL;
function ActiveClass_Get_ActiveClassParent(): PAnsiChar; CDECL;

implementation

uses
    CAPI_Constants,
    DSSGlobals,
    DSSObject,
    CktElement,
    PCClass, 
    PDClass, 
    MeterClass, 
    ControlClass;

procedure ActiveClass_Get_AllNames(var ResultPtr: PPAnsiChar; ResultCount: PInteger); CDECL;
var
    Result: PPAnsiCharArray;
    idx: Integer;
    k: Integer;

begin
    if (ActiveCircuit <> NIL) and Assigned(ActiveDSSClass) then
        with ActiveCircuit do
        begin
            Result := DSS_RecreateArray_PPAnsiChar(ResultPtr, ResultCount, ActiveDSSClass.ElementCount);
            k := 0;
            idx := ActiveDSSClass.First;
            while idx > 0 do
            begin
                Result[k] := DSS_CopyStringAsPChar(ActiveDSSObject.Name);
                Inc(k);
                idx := ActiveDSSClass.Next;
            end;
        end
    else
        Result := DSS_RecreateArray_PPAnsiChar(ResultPtr, ResultCount, 1);

end;

procedure ActiveClass_Get_AllNames_GR(); CDECL;
// Same as ActiveClass_Get_AllNames but uses global result (GR) pointers
begin
    ActiveClass_Get_AllNames(GR_DataPtr_PPAnsiChar, GR_CountPtr_PPAnsiChar)
end;

//------------------------------------------------------------------------------
function ActiveClass_Get_First(): Integer; CDECL;
begin

    Result := 0;
    if (ActiveCircuit <> NIL) and Assigned(ActiveDSSClass) then
    begin
        Result := ActiveDSSClass.First;  // sets active objects
    end;

end;
//------------------------------------------------------------------------------
function ActiveClass_Get_Next(): Integer; CDECL;
begin

    Result := 0;
    if (ActiveCircuit <> NIL) and Assigned(ActiveDSSClass) then
    begin
        Result := ActiveDSSClass.Next;  // sets active objects
    end;

end;
//------------------------------------------------------------------------------
function ActiveClass_Get_Name_AnsiString(): Ansistring; inline;
begin
    if Assigned(ActiveDSSObject) then
        Result := ActiveDSSObject.Name
    else
        Result := '';
end;

function ActiveClass_Get_Name(): PAnsiChar; CDECL;
begin
    Result := DSS_GetAsPAnsiChar(ActiveClass_Get_Name_AnsiString());
end;
//------------------------------------------------------------------------------
procedure ActiveClass_Set_Name(const Value: PAnsiChar); CDECL;
// set object active by name
var
    pelem: TDSSObject;
begin
    if Assigned(ActiveDSSClass) then
    begin
        pelem := ActiveDSSClass.Find(Value);
        if pelem <> NIL then
        begin
            if pelem is TDSSCktElement then
                ActiveCircuit.ActiveCktElement := TDSSCktElement(pelem)  // sets ActiveDSSobject
            else
                ActiveDSSObject := pelem;
        end;
    end;
end;
//------------------------------------------------------------------------------
function ActiveClass_Get_NumElements(): Integer; CDECL;
begin
    if Assigned(ActiveDSSClass) then
        Result := ActiveDSSCLass.ElementCount
    else
        Result := 0;
end;
//------------------------------------------------------------------------------
function ActiveClass_Get_ActiveClassName_AnsiString(): Ansistring; inline;
begin
    if Assigned(ActiveDSSClass) then
        Result := ActiveDSSCLass.Name
    else
        Result := '';
end;

function ActiveClass_Get_ActiveClassName(): PAnsiChar; CDECL;
begin
    Result := DSS_GetAsPAnsiChar(ActiveClass_Get_ActiveClassName_AnsiString());
end;
//------------------------------------------------------------------------------
function ActiveClass_Get_Count(): Integer; CDECL;
begin
    if Assigned(ActiveDSSClass) then
        Result := ActiveDSSCLass.ElementCount
    else
        Result := 0;
end;
//------------------------------------------------------------------------------
function ActiveClass_Get_ActiveClassParent(): PAnsiChar;
begin
    if Assigned(ActiveDSSClass) then
    begin
        Result := PAnsiChar('Generic Object');
        if ActiveDSSClass.ClassType.InheritsFrom(TPCClass) then
            Result := PAnsiChar('TPCClas'); //NOTE: kept as "Clas" for compatibility
        if ActiveDSSClass.ClassType.InheritsFrom(TPDClass) then
            Result := PAnsiChar('TPDClass');
        if ActiveDSSClass.ClassType.InheritsFrom(TMeterClass) then
            Result := PAnsiChar('TMeterClass');
        if ActiveDSSClass.ClassType.InheritsFrom(TControlClass) then
            Result := PAnsiChar('TControlClass');
    end
    else 
        Result := PAnsiChar(AnsiString('Parent Class unknonwn'));
end;
//------------------------------------------------------------------------------
end.
