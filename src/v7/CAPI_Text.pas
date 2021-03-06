unit CAPI_Text;

{$inline on}

interface

uses
    CAPI_Utils;

function Text_Get_Command(): PAnsiChar; CDECL;
procedure Text_Set_Command(const Value: PAnsiChar); CDECL;
function Text_Get_Result(): PAnsiChar; CDECL;

implementation

uses
    CAPI_Constants,
    DSSGlobals,
    Executive,
    SysUtils;

const
    nothing: Ansistring = #0#0;

function Text_Get_Command_AnsiString(): Ansistring; inline;
begin
    Result := DSSExecutive.Command;
end;

function Text_Get_Command(): PAnsiChar; CDECL;
begin
    Result := DSS_GetAsPAnsiChar(Text_Get_Command_AnsiString());
end;
//------------------------------------------------------------------------------
procedure Text_Set_Command(const Value: PAnsiChar); CDECL;
begin
    SolutionAbort := FALSE;  // Reset for commands entered from outside
    DSSExecutive.Command := Value;  {Convert to String}
end;
//------------------------------------------------------------------------------
function Text_Get_Result_AnsiString(): Ansistring; inline;
begin
    if Length(GlobalResult) < 1 then
        Result := nothing
    else
        Result := GlobalResult;
    {****}
    {
      Need to implement a protocol for determining whether to go get the
      result from a file or to issue another DSS command to get the value
      from operations where the result is voluminous.
    }

end;

function Text_Get_Result(): PAnsiChar; CDECL;
begin
    Result := DSS_GetAsPAnsiChar(Text_Get_Result_AnsiString());
end;
//------------------------------------------------------------------------------
end.
