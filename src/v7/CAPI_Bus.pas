unit CAPI_Bus;

{$inline on}

interface

uses
    CAPI_Utils;

function Bus_Get_Name(): PAnsiChar; CDECL;
function Bus_Get_NumNodes(): Integer; CDECL;
procedure Bus_Get_SeqVoltages(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
procedure Bus_Get_SeqVoltages_GR(); CDECL;
procedure Bus_Get_Voltages(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
procedure Bus_Get_Voltages_GR(); CDECL;
procedure Bus_Get_Nodes(var ResultPtr: PInteger; ResultCount: PInteger); CDECL;
procedure Bus_Get_Nodes_GR(); CDECL;
procedure Bus_Get_Isc(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
procedure Bus_Get_Isc_GR(); CDECL;
procedure Bus_Get_Voc(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
procedure Bus_Get_Voc_GR(); CDECL;
function Bus_Get_kVBase(): Double; CDECL;
procedure Bus_Get_puVoltages(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
procedure Bus_Get_puVoltages_GR(); CDECL;
procedure Bus_Get_Zsc0(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
procedure Bus_Get_Zsc0_GR(); CDECL;
procedure Bus_Get_Zsc1(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
procedure Bus_Get_Zsc1_GR(); CDECL;
procedure Bus_Get_ZscMatrix(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
procedure Bus_Get_ZscMatrix_GR(); CDECL;
function Bus_ZscRefresh(): Wordbool; CDECL;
procedure Bus_Get_YscMatrix(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
procedure Bus_Get_YscMatrix_GR(); CDECL;
function Bus_Get_Coorddefined(): Wordbool; CDECL;
function Bus_Get_x(): Double; CDECL;
procedure Bus_Set_x(Value: Double); CDECL;
function Bus_Get_y(): Double; CDECL;
procedure Bus_Set_y(Value: Double); CDECL;
function Bus_Get_Distance(): Double; CDECL;
function Bus_GetUniqueNodeNumber(StartNumber: Integer): Integer; CDECL;
procedure Bus_Get_CplxSeqVoltages(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
procedure Bus_Get_CplxSeqVoltages_GR(); CDECL;
function Bus_Get_Int_Duration(): Double; CDECL;
function Bus_Get_Lambda(): Double; CDECL;
function Bus_Get_Cust_Duration(): Double; CDECL;
function Bus_Get_Cust_Interrupts(): Double; CDECL;
function Bus_Get_N_Customers(): Integer; CDECL;
function Bus_Get_N_interrupts(): Double; CDECL;
procedure Bus_Get_puVLL(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
procedure Bus_Get_puVLL_GR(); CDECL;
procedure Bus_Get_VLL(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
procedure Bus_Get_VLL_GR(); CDECL;
procedure Bus_Get_puVmagAngle(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
procedure Bus_Get_puVmagAngle_GR(); CDECL;
procedure Bus_Get_VMagAngle(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
procedure Bus_Get_VMagAngle_GR(); CDECL;
function Bus_Get_TotalMiles(): Double; CDECL;
function Bus_Get_SectionID(): Integer; CDECL;
function Bus_Get_Next(): Integer; CDECL; // API Extension

implementation

uses
    CAPI_Constants,
    DSSGlobals,
    Circuit,
    Ucomplex,
    MathUtil,
    sysutils,
    ExecHelper,
    SolutionAlgs,
    Utilities,
    Bus;

function Bus_Get_Name_AnsiString(): Ansistring; inline;
begin
    Result := '';

    if (ActiveCircuit <> NIL) then
        with ActiveCircuit do
            if (ActiveBusIndex > 0) and (ActiveBusIndex <= NumBuses) then
                Result := BusList.Get(ActiveBusIndex);
end;

function Bus_Get_Name(): PAnsiChar; CDECL;
begin
    Result := DSS_GetAsPAnsiChar(Bus_Get_Name_AnsiString());
end;
//------------------------------------------------------------------------------
function Bus_Get_NumNodes(): Integer; CDECL;
begin
    Result := 0;
    if (ActiveCircuit <> NIL) then
        with ActiveCircuit do
            if (ActiveBusIndex > 0) and (ActiveBusIndex <= NumBuses) then
                Result := ActiveCircuit.Buses^[ActiveCircuit.ActiveBusIndex].NumNodesThisBus;

end;
//------------------------------------------------------------------------------
procedure Bus_Get_SeqVoltages(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
// Compute sequence voltages for Active Bus
// magnitude only
// returns a set of seq voltages (3)
var
    Result: PDoubleArray;
    Nvalues, i, iV: Integer;
    VPh, V012: array[1..3] of Complex;

begin
    if (ActiveCircuit = NIL) or 
        (not ((ActiveCircuit.ActiveBusIndex > 0) and (ActiveCircuit.ActiveBusIndex <= ActiveCircuit.NumBuses))) then
    begin
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
        Exit;
    end;

    with ActiveCircuit do
    begin
        Nvalues := Buses^[ActiveBusIndex].NumNodesThisBus;
        if Nvalues > 3 then
            Nvalues := 3;

        // Assume nodes 1, 2, and 3 are the 3 phases
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 3);
        if Nvalues <> 3 then
            for i := 1 to 3 do
                Result[i - 1] := -1.0  // Signify seq voltages n/A for less then 3 phases
        else
        begin
            iV := 0;
            for i := 1 to 3 do
            begin
                Vph[i] := Solution.NodeV^[Buses^[ActiveBusIndex].Find(i)];
            end;

            Phase2SymComp(@Vph, @V012);   // Compute Symmetrical components

            for i := 1 to 3 do  // Stuff it in the result
            begin
                Result[iV] := Cabs(V012[i]);
                Inc(iV);
            end;
        end;
    end
end;

procedure Bus_Get_SeqVoltages_GR(); CDECL;
// Same as Bus_Get_SeqVoltages but uses global result (GR) pointers
begin
    Bus_Get_SeqVoltages(GR_DataPtr_PDouble, GR_CountPtr_PDouble)
end;

//------------------------------------------------------------------------------
procedure Bus_Get_Voltages(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
// Return Complex for all nodes of voltages for Active Bus
var
    Result: PDoubleArray;
    Nvalues, i, iV, NodeIdx, jj: Integer;
    Volts: Complex;
    pBus: TDSSBus;

begin
    if (ActiveCircuit = NIL) or 
        (not ((ActiveCircuit.ActiveBusIndex > 0) and (ActiveCircuit.ActiveBusIndex <= ActiveCircuit.NumBuses))) then
    begin
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
        Exit;
    end;

    with ActiveCircuit do
    begin
        pBus := Buses^[ActiveBusIndex];
        Nvalues := pBus.NumNodesThisBus;
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 2 * NValues);
        iV := 0;
        jj := 1;
        with pBus do
            for i := 1 to NValues do
            begin
                // this code so nodes come out in order from smallest to larges
                repeat
                    NodeIdx := FindIdx(jj);  // Get the index of the Node that matches jj
                    inc(jj)
                until NodeIdx > 0;

                Volts := Solution.NodeV^[GetRef(NodeIdx)];  // referenced to pBus
                Result[iV] := Volts.re;
                Inc(iV);
                Result[iV] := Volts.im;
                Inc(iV);
            end;
    end
end;

procedure Bus_Get_Voltages_GR(); CDECL;
// Same as Bus_Get_Voltages but uses global result (GR) pointers
begin
    Bus_Get_Voltages(GR_DataPtr_PDouble, GR_CountPtr_PDouble)
end;

//------------------------------------------------------------------------------
procedure Bus_Get_Nodes(var ResultPtr: PInteger; ResultCount: PInteger); CDECL;
// return array of node numbers corresponding to voltages
var
    Result: PIntegerArray;
    Nvalues, i, iV, NodeIdx, jj: Integer;
    pBus: TDSSBus;

begin
    if (ActiveCircuit = NIL) or 
        (not ((ActiveCircuit.ActiveBusIndex > 0) and (ActiveCircuit.ActiveBusIndex <= ActiveCircuit.NumBuses))) then
    begin
        Result := DSS_RecreateArray_PInteger(ResultPtr, ResultCount, 1);
        Exit;
    end;

    with ActiveCircuit do
    begin
        pBus := Buses^[ActiveBusIndex];
        with pBus do
        begin
            Nvalues := NumNodesThisBus;
            Result := DSS_RecreateArray_PInteger(ResultPtr, ResultCount, NValues);
            iV := 0;
            jj := 1;
            for i := 1 to NValues do
            begin
                // this code so nodes come out in order from smallest to larges
                repeat
                    NodeIdx := FindIdx(jj);  // Get the index of the Node that matches jj
                    inc(jj)
                until NodeIdx > 0;
                Result[iV] := Buses^[ActiveBusIndex].GetNum(NodeIdx);
                Inc(iV);
            end;
        end;
    end
end;

procedure Bus_Get_Nodes_GR(); CDECL;
// Same as Bus_Get_Nodes but uses global result (GR) pointers
begin
    Bus_Get_Nodes(GR_DataPtr_PInteger, GR_CountPtr_PInteger)
end;

//------------------------------------------------------------------------------
procedure Bus_Get_Isc(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
// Return the short circuit current
var
    Result: PDoubleArray;
    Isc: Complex;
    i, iV, NValues: Integer;

begin
    if (ActiveCircuit = NIL) or 
        (not ((ActiveCircuit.ActiveBusIndex > 0) and (ActiveCircuit.ActiveBusIndex <= ActiveCircuit.NumBuses))) then
    begin
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
        Exit;
    end;

    with ActiveCircuit do
    begin
        if Buses^[ActiveBusIndex].BusCurrent <> NIL then
        begin
            NValues := Buses^[ActiveBusIndex].NumNodesThisBus;
            Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 2 * NValues);
            iV := 0;
            for i := 1 to NValues do
            begin
                Isc := Buses^[ActiveBusIndex].BusCurrent^[i];
                Result[iV] := Isc.Re;
                Inc(iV);
                Result[iV] := Isc.Im;
                Inc(iV);
            end;
        end
        else
            Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
    end
end;

procedure Bus_Get_Isc_GR(); CDECL;
// Same as Bus_Get_Isc but uses global result (GR) pointers
begin
    Bus_Get_Isc(GR_DataPtr_PDouble, GR_CountPtr_PDouble)
end;

//------------------------------------------------------------------------------
procedure Bus_Get_Voc(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
// Return the Open circuit Voltage for this bus
var
    Result: PDoubleArray;
    Voc: Complex;
    i, iV, NValues: Integer;

begin
    if (ActiveCircuit = NIL) or 
        (not ((ActiveCircuit.ActiveBusIndex > 0) and (ActiveCircuit.ActiveBusIndex <= ActiveCircuit.NumBuses))) then
    begin
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
        Exit;
    end;

    with ActiveCircuit do
    begin
        if Buses^[ActiveBusIndex].VBus <> NIL then
        begin
            NValues := Buses^[ActiveBusIndex].NumNodesThisBus;
            Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 2 * NValues);
            iV := 0;
            for i := 1 to NValues do
            begin
                Voc := Buses^[ActiveBusIndex].VBus^[i];
                Result[iV] := Voc.Re;
                Inc(iV);
                Result[iV] := Voc.Im;
                Inc(iV);
            end;
        end
        else
            Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
    end
end;

procedure Bus_Get_Voc_GR(); CDECL;
// Same as Bus_Get_Voc but uses global result (GR) pointers
begin
    Bus_Get_Voc(GR_DataPtr_PDouble, GR_CountPtr_PDouble)
end;

//------------------------------------------------------------------------------
function Bus_Get_kVBase(): Double; CDECL;
begin
    Result := 0.0;
    if (ActiveCircuit <> NIL) then
        with ActiveCircuit do
            if (ActiveBusIndex > 0) and (ActiveBusIndex <= NumBuses) then
                Result := ActiveCircuit.Buses^[ActiveCircuit.ActiveBusIndex].kVBase;

end;
//------------------------------------------------------------------------------
procedure Bus_Get_puVoltages(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
// Returns voltages at bus in per unit.  However, if kVBase=0, returns actual volts
var
    Result: PDoubleArray;
    Nvalues, i, iV, NodeIdx, jj: Integer;
    Volts: Complex;
    BaseFactor: Double;
    pBus: TDSSBus;

begin
    if (ActiveCircuit = NIL) or 
        (not ((ActiveCircuit.ActiveBusIndex > 0) and (ActiveCircuit.ActiveBusIndex <= ActiveCircuit.NumBuses))) then
    begin
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
        Exit;
    end;

    with ActiveCircuit do
    begin
        pBus := Buses^[ActiveBusIndex];
        with pBus do
        begin
            Nvalues := NumNodesThisBus;
            Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 2 * NValues);
            iV := 0;
            jj := 1;
            if kVBase > 0.0 then
                BaseFactor := 1000.0 * kVBase
            else
                BaseFactor := 1.0;
            for i := 1 to NValues do
            begin
                // this code so nodes come out in order from smallest to larges
                repeat
                    NodeIdx := FindIdx(jj);  // Get the index of the Node that matches jj
                    inc(jj)
                until NodeIdx > 0;

                Volts := Solution.NodeV^[GetRef(NodeIdx)];
                Result[iV] := Volts.re / BaseFactor;
                Inc(iV);
                Result[iV] := Volts.im / BaseFactor;
                Inc(iV);
            end;
        end;
    end;
end;

procedure Bus_Get_puVoltages_GR(); CDECL;
// Same as Bus_Get_puVoltages but uses global result (GR) pointers
begin
    Bus_Get_puVoltages(GR_DataPtr_PDouble, GR_CountPtr_PDouble)
end;

//------------------------------------------------------------------------------
procedure Bus_Get_Zsc0(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
var
    Result: PDoubleArray;
    Z: Complex;

begin
    if (ActiveCircuit = NIL) or 
        (not ((ActiveCircuit.ActiveBusIndex > 0) and (ActiveCircuit.ActiveBusIndex <= ActiveCircuit.NumBuses))) then
    begin
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
        Exit;
    end;

    with ActiveCircuit do
    begin
        Z := Buses^[ActiveBusIndex].Zsc0;
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 2);
        Result[0] := Z.Re;
        Result[1] := Z.Im;
    end
end;

procedure Bus_Get_Zsc0_GR(); CDECL;
// Same as Bus_Get_Zsc0 but uses global result (GR) pointers
begin
    Bus_Get_Zsc0(GR_DataPtr_PDouble, GR_CountPtr_PDouble)
end;

//------------------------------------------------------------------------------
procedure Bus_Get_Zsc1(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
var
    Result: PDoubleArray;
    Z: Complex;
begin
    if (ActiveCircuit = NIL) or 
        (not ((ActiveCircuit.ActiveBusIndex > 0) and (ActiveCircuit.ActiveBusIndex <= ActiveCircuit.NumBuses))) then
    begin
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
        Exit;
    end;
    
    with ActiveCircuit do
    begin
        Z := Buses^[ActiveBusIndex].Zsc1;
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 2);
        Result[0] := Z.Re;
        Result[1] := Z.Im;
    end
end;

procedure Bus_Get_Zsc1_GR(); CDECL;
// Same as Bus_Get_Zsc1 but uses global result (GR) pointers
begin
    Bus_Get_Zsc1(GR_DataPtr_PDouble, GR_CountPtr_PDouble)
end;

//------------------------------------------------------------------------------
procedure Bus_Get_ZscMatrix(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
var
    Result: PDoubleArray;
    Nelements, iV, i, j: Integer;
    Z: Complex;

begin
    Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
    if (ActiveCircuit = NIL) or 
        (not ((ActiveCircuit.ActiveBusIndex > 0) and (ActiveCircuit.ActiveBusIndex <= ActiveCircuit.NumBuses))) then
        Exit;

    try
        with ActiveCircuit do
        begin
            if Assigned(Buses^[ActiveBusIndex].Zsc) then
            begin
                Nelements := Buses^[ActiveBusIndex].Zsc.Order;
                Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 2 * Nelements * Nelements);
                iV := 0;
                with Buses^[ActiveBusIndex] do
                    for i := 1 to Nelements do
                        for j := 1 to Nelements do
                        begin
                            Z := Zsc.GetElement(i, j);
                            Result[iV] := Z.Re;
                            Inc(iV);
                            Result[iV] := Z.Im;
                            Inc(iV);
                        end;
            end
        end
    except
        On E: Exception do
            DoSimpleMsg('ZscMatrix Error: ' + E.message + CRLF, 5016);
    end;
end;

procedure Bus_Get_ZscMatrix_GR(); CDECL;
// Same as Bus_Get_ZscMatrix but uses global result (GR) pointers
begin
    Bus_Get_ZscMatrix(GR_DataPtr_PDouble, GR_CountPtr_PDouble)
end;

//------------------------------------------------------------------------------
function Bus_ZscRefresh(): Wordbool; CDECL;
begin

    Result := FALSE;   // Init in case of failure

    if ExecHelper.DoZscRefresh = 0 then
        Result := TRUE;

end;
//------------------------------------------------------------------------------
procedure Bus_Get_YscMatrix(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
var
    Result: PDoubleArray;
    Nelements, iV, i, j: Integer;
    Y1: Complex;

begin
    Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
    if (ActiveCircuit = NIL) or 
        (not ((ActiveCircuit.ActiveBusIndex > 0) and (ActiveCircuit.ActiveBusIndex <= ActiveCircuit.NumBuses))) then
        Exit;

    try
        with ActiveCircuit do
            if Assigned(Buses^[ActiveBusIndex].Ysc) then
            begin
                Nelements := Buses^[ActiveBusIndex].Ysc.Order;
                Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 2 * Nelements * Nelements);
                iV := 0;
                with Buses^[ActiveBusIndex] do
                    for i := 1 to Nelements do
                        for j := 1 to Nelements do
                        begin
                            Y1 := Ysc.GetElement(i, j);
                            Result[iV] := Y1.Re;
                            Inc(iV);
                            Result[iV] := Y1.Im;
                            Inc(iV);
                        end;

            end
    except
        On E: Exception do
            DoSimpleMsg('ZscMatrix Error: ' + E.message + CRLF, 5017);
    end;
end;

procedure Bus_Get_YscMatrix_GR(); CDECL;
// Same as Bus_Get_YscMatrix but uses global result (GR) pointers
begin
    Bus_Get_YscMatrix(GR_DataPtr_PDouble, GR_CountPtr_PDouble)
end;

//------------------------------------------------------------------------------
function Bus_Get_Coorddefined(): Wordbool; CDECL;
begin
    Result := FALSE;
    if (ActiveCircuit <> NIL) then
        with ActiveCircuit do
            if (ActiveBusIndex > 0) and (ActiveBusIndex <= NumBuses) then
                if (Buses^[ActiveCircuit.ActiveBusIndex].CoordDefined) then
                    Result := TRUE;
end;
//------------------------------------------------------------------------------
function Bus_Get_x(): Double; CDECL;
begin
    Result := 0.0;
    if (ActiveCircuit <> NIL) then
        with ActiveCircuit do
            if (ActiveBusIndex > 0) and (ActiveBusIndex <= NumBuses) then
                if (Buses^[ActiveCircuit.ActiveBusIndex].CoordDefined) then
                    Result := Buses^[ActiveCircuit.ActiveBusIndex].x;
end;
//------------------------------------------------------------------------------
procedure Bus_Set_x(Value: Double); CDECL;
begin
    if (ActiveCircuit <> NIL) then
        with ActiveCircuit do
            if (ActiveBusIndex > 0) and (ActiveBusIndex <= NumBuses) then
            begin
                Buses^[ActiveCircuit.ActiveBusIndex].CoordDefined := TRUE;
                Buses^[ActiveCircuit.ActiveBusIndex].x := Value;
            end;
end;
//------------------------------------------------------------------------------
function Bus_Get_y(): Double; CDECL;
begin
    Result := 0.0;
    if (ActiveCircuit <> NIL) then
        with ActiveCircuit do
            if (ActiveBusIndex > 0) and (ActiveBusIndex <= NumBuses) then
                if (Buses^[ActiveCircuit.ActiveBusIndex].CoordDefined) then
                    Result := Buses^[ActiveCircuit.ActiveBusIndex].y;
end;
//------------------------------------------------------------------------------
procedure Bus_Set_y(Value: Double); CDECL;
begin
    if (ActiveCircuit <> NIL) then
        with ActiveCircuit do
            if (ActiveBusIndex > 0) and (ActiveBusIndex <= NumBuses) then
            begin
                Buses^[ActiveBusIndex].CoordDefined := TRUE;
                Buses^[ActiveBusIndex].y := Value;
            end;
end;
//------------------------------------------------------------------------------
function Bus_Get_Distance(): Double; CDECL;
begin
    Result := 0.0;
    if (ActiveCircuit <> NIL) then
        with ActiveCircuit do
            if ((ActiveBusIndex > 0) and (ActiveBusIndex <= NumBuses)) then
                Result := Buses^[ActiveBusIndex].DistFromMeter;
end;
//------------------------------------------------------------------------------
function Bus_GetUniqueNodeNumber(StartNumber: Integer): Integer; CDECL;
begin
    if ActiveCircuit <> NIL then
        with ActiveCircuit do

            if ActiveBusIndex > 0 then
                Result := Utilities.GetUniqueNodeNumber(BusList.Get(ActiveBusIndex), StartNumber);
end;
//------------------------------------------------------------------------------
procedure Bus_Get_CplxSeqVoltages(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
// Compute sequence voltages for Active Bus
// Complex values
// returns a set of seq voltages (3) in 0, 1, 2 order
var
    Result: PDoubleArray;
    Nvalues, i, iV: Integer;
    VPh, V012: array[1..3] of Complex;

begin
    if (ActiveCircuit = NIL) or 
        (not ((ActiveCircuit.ActiveBusIndex > 0) and (ActiveCircuit.ActiveBusIndex <= ActiveCircuit.NumBuses))) then
    begin
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
        Exit;
    end;

    with ActiveCircuit do
    begin
        Nvalues := Buses^[ActiveBusIndex].NumNodesThisBus;
        if Nvalues > 3 then
            Nvalues := 3;

        // Assume nodes labelled 1, 2, and 3 are the 3 phases
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 6);
        if Nvalues <> 3 then
            for i := 1 to 6 do
                Result[i - 1] := -1.0  // Signify seq voltages n/A for less then 3 phases
        else
        begin
            iV := 0;
            for i := 1 to 3 do
                Vph[i] := Solution.NodeV^[Buses^[ActiveBusIndex].Find(i)];

            Phase2SymComp(@Vph, @V012);   // Compute Symmetrical components

            for i := 1 to 3 do  // Stuff it in the result
            begin
                Result[iV] := V012[i].re;
                Inc(iV);
                Result[iV] := V012[i].im;
                Inc(iV);
            end;
        end;
    end
end;

procedure Bus_Get_CplxSeqVoltages_GR(); CDECL;
// Same as Bus_Get_CplxSeqVoltages but uses global result (GR) pointers
begin
    Bus_Get_CplxSeqVoltages(GR_DataPtr_PDouble, GR_CountPtr_PDouble)
end;

//------------------------------------------------------------------------------
function Bus_Get_Int_Duration(): Double; CDECL;
begin
    Result := 0.0;
    if ActiveCircuit <> NIL then
        with ActiveCircuit do
            if ActiveBusIndex > 0 then
                Result := Buses^[ActiveBusIndex].Bus_Int_Duration;
end;
//------------------------------------------------------------------------------
function Bus_Get_Lambda(): Double; CDECL;
begin
    Result := 0.0;
    if ActiveCircuit <> NIL then
        with ActiveCircuit do
            if ActiveBusIndex > 0 then
                Result := Buses^[ActiveBusIndex].BusFltRate;
end;
//------------------------------------------------------------------------------
function Bus_Get_Cust_Duration(): Double; CDECL;
begin
    Result := 0.0;
    if ActiveCircuit <> NIL then
        with ActiveCircuit do
            if ActiveBusIndex > 0 then
                Result := Buses^[ActiveBusIndex].BusCustDurations;
end;
//------------------------------------------------------------------------------
function Bus_Get_Cust_Interrupts(): Double; CDECL;
begin
    Result := 0.0;
    if ActiveCircuit <> NIL then
        with ActiveCircuit do
            if ActiveBusIndex > 0 then
                Result := Buses^[ActiveBusIndex].BusCustDurations;
end;
//------------------------------------------------------------------------------
function Bus_Get_N_Customers(): Integer; CDECL;
begin
    Result := 0;
    if ActiveCircuit <> NIL then
        with ActiveCircuit do
            if ActiveBusIndex > 0 then
                Result := Buses^[ActiveBusIndex].BusTotalNumCustomers;
end;
//------------------------------------------------------------------------------
function Bus_Get_N_interrupts(): Double; CDECL;
begin
    Result := 0.0;
    if ActiveCircuit <> NIL then
        with ActiveCircuit do
            if ActiveBusIndex > 0 then
                Result := Buses^[ActiveBusIndex].Bus_Num_Interrupt;
end;
//------------------------------------------------------------------------------
procedure Bus_Get_puVLL(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
var
    Result: PDoubleArray;
    Nvalues, i, iV, NodeIdxi, NodeIdxj, jj, k: Integer;
    Volts: Complex;
    pBus: TDSSBus;
    BaseFactor: Double;

begin
    if (ActiveCircuit = NIL) or 
        (not ((ActiveCircuit.ActiveBusIndex > 0) and (ActiveCircuit.ActiveBusIndex <= ActiveCircuit.NumBuses))) then
    begin
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
        Exit;
    end;

    with ActiveCircuit do
    begin
        pBus := Buses^[ActiveBusIndex];
        Nvalues := pBus.NumNodesThisBus;
        if Nvalues > 3 then
            Nvalues := 3;

        if Nvalues > 1 then
        begin
            if Nvalues = 2 then
                Nvalues := 1;  // only one L-L voltage if 2 phase
            Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 2 * NValues);
            iV := 0;
            with pBus do
            begin
                if kVBase > 0.0 then
                    BaseFactor := 1000.0 * kVBase * sqrt3
                else
                    BaseFactor := 1.0;

                for i := 1 to NValues do     // for 2- or 3-phases
                begin
          // this code assumes the nodes are ordered 1, 2, 3
//------------------------------------------------------------------------------------------------
// This section was added to prevent measuring using disconnected nodes, for example, if the
// bus has 2 nodes but those are 1 and 3, that will bring a problem.

                    jj := i;
                    repeat
                        NodeIdxi := FindIdx(jj);  // Get the index of the Node that matches i
                        inc(jj);
                    until NodeIdxi > 0;
                    
                    // (2020-03-01) Changed in DSS C-API to avoid some corner 
                    // cases that resulted in infinite loops
                    for k := 1 to 3 do
                    begin
                        NodeIdxj := FindIdx(jj);  // Get the index of the Node that matches i
                        if jj > 3 then
                            jj := 1
                        else
                            inc(jj);

                        if NodeIdxj > 0 then 
                            break;
                    end;
                    if NodeIdxj = 0 then
                    begin
                        // Could not find appropriate node
                        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
                        Exit;
                    end;
//------------------------------------------------------------------------------------------------
                    with Solution do
                        Volts := Csub(NodeV^[GetRef(NodeIdxi)], NodeV^[GetRef(NodeIdxj)]);
                    Result[iV] := Volts.re / BaseFactor;
                    Inc(iV);
                    Result[iV] := Volts.im / BaseFactor;
                    Inc(iV);
                end;
            end;  {With pBus}
        end
        else
        begin  // for 1-phase buses, do not attempt to compute.
            Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 2);  // just return -1's in array
            Result[0] := -99999.0;
            Result[1] := 0.0;
        end;
    end
end;

procedure Bus_Get_puVLL_GR(); CDECL;
// Same as Bus_Get_puVLL but uses global result (GR) pointers
begin
    Bus_Get_puVLL(GR_DataPtr_PDouble, GR_CountPtr_PDouble)
end;

//------------------------------------------------------------------------------
procedure Bus_Get_VLL(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
var
    Result: PDoubleArray;
    Nvalues, i, iV, NodeIdxi, NodeIdxj, jj, k: Integer;
    Volts: Complex;
    pBus: TDSSBus;
begin
    if (ActiveCircuit = NIL) or 
        (not ((ActiveCircuit.ActiveBusIndex > 0) and (ActiveCircuit.ActiveBusIndex <= ActiveCircuit.NumBuses))) then
    begin
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
        Exit;
    end;

    with ActiveCircuit do
    begin
        pBus := Buses^[ActiveBusIndex];
        Nvalues := pBus.NumNodesThisBus;
        if Nvalues > 3 then
            Nvalues := 3;

        if Nvalues > 1 then
        begin
            if Nvalues = 2 then
                Nvalues := 1;  // only one L-L voltage if 2 phase
            Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 2 * NValues);
            iV := 0;
            with pBus do
                for i := 1 to NValues do     // for 2- or 3-phases
                begin
          // this code assumes the nodes are ordered 1, 2, 3
//------------------------------------------------------------------------------------------------
// This section was added to prevent measuring using disconnected nodes, for example, if the
// bus has 2 nodes but those are 1 and 3, that will bring a problem.

                    jj := i;
                    repeat
                        NodeIdxi := FindIdx(jj);  // Get the index of the Node that matches i
                        inc(jj);
                    until NodeIdxi > 0;
                    
                    // (2020-03-01) Changed in DSS C-API to avoid some corner 
                    // cases that resulted in infinite loops
                    for k := 1 to 3 do
                    begin
                        NodeIdxj := FindIdx(jj);  // Get the index of the Node that matches i
                        if jj > 3 then
                            jj := 1
                        else
                            inc(jj);

                        if NodeIdxj > 0 then 
                            break;
                    end;
                    if NodeIdxj = 0 then
                    begin
                        // Could not find appropriate node
                        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
                        Exit;
                    end;
//------------------------------------------------------------------------------------------------
                    with Solution do
                        Volts := Csub(NodeV^[GetRef(NodeIdxi)], NodeV^[GetRef(NodeIdxj)]);
                    Result[iV] := Volts.re;
                    Inc(iV);
                    Result[iV] := Volts.im;
                    Inc(iV);
                end;
        end
        else
        begin  // for 1-phase buses, do not attempt to compute.
            Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 2);  // just return -1's in array
            Result[0] := -99999.0;
            Result[1] := 0.0;
        end;
    end
end;

procedure Bus_Get_VLL_GR(); CDECL;
// Same as Bus_Get_VLL but uses global result (GR) pointers
begin
    Bus_Get_VLL(GR_DataPtr_PDouble, GR_CountPtr_PDouble)
end;

//------------------------------------------------------------------------------
procedure Bus_Get_puVmagAngle(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
// Return mag/angle for all nodes of voltages for Active Bus
var
    Result: PDoubleArray;
    Nvalues, i, iV, NodeIdx, jj: Integer;
    Volts: polar;
    pBus: TDSSBus;
    Basefactor: Double;

begin
    if (ActiveCircuit = NIL) or 
        (not ((ActiveCircuit.ActiveBusIndex > 0) and (ActiveCircuit.ActiveBusIndex <= ActiveCircuit.NumBuses))) then
    begin
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
        Exit;
    end;

    with ActiveCircuit do
    begin
        pBus := Buses^[ActiveBusIndex];
        Nvalues := pBus.NumNodesThisBus;
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 2 * NValues);
        iV := 0;
        jj := 1;
        with pBus do
        begin
            if kVBase > 0.0 then
                BaseFactor := 1000.0 * kVBase
            else
                BaseFactor := 1.0;

            for i := 1 to NValues do
            begin
                // this code so nodes come out in order from smallest to larges
                repeat
                    NodeIdx := FindIdx(jj);  // Get the index of the Node that matches jj
                    inc(jj)
                until NodeIdx > 0;

                Volts := ctopolardeg(Solution.NodeV^[GetRef(NodeIdx)]);  // referenced to pBus
                Result[iV] := Volts.mag / BaseFactor;
                Inc(iV);
                Result[iV] := Volts.ang;
                Inc(iV);
            end;
        end;
    end
end;

procedure Bus_Get_puVmagAngle_GR(); CDECL;
// Same as Bus_Get_puVmagAngle but uses global result (GR) pointers
begin
    Bus_Get_puVmagAngle(GR_DataPtr_PDouble, GR_CountPtr_PDouble)
end;

//------------------------------------------------------------------------------
procedure Bus_Get_VMagAngle(var ResultPtr: PDouble; ResultCount: PInteger); CDECL;
// Return mag/angle for all nodes of voltages for Active Bus
var
    Result: PDoubleArray;
    Nvalues, i, iV, NodeIdx, jj: Integer;
    Volts: polar;
    pBus: TDSSBus;

begin
    if (ActiveCircuit = NIL) or 
        (not ((ActiveCircuit.ActiveBusIndex > 0) and (ActiveCircuit.ActiveBusIndex <= ActiveCircuit.NumBuses))) then
    begin
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 1);
        Exit;
    end;
    
    with ActiveCircuit do
    begin
        pBus := Buses^[ActiveBusIndex];
        Nvalues := pBus.NumNodesThisBus;
        Result := DSS_RecreateArray_PDouble(ResultPtr, ResultCount, 2 * NValues);
        iV := 0;
        jj := 1;
        with pBus do
            for i := 1 to NValues do
            begin
                // this code so nodes come out in order from smallest to larges
                repeat
                    NodeIdx := FindIdx(jj);  // Get the index of the Node that matches jj
                    inc(jj)
                until NodeIdx > 0;

                Volts := ctopolardeg(Solution.NodeV^[GetRef(NodeIdx)]);  // referenced to pBus
                Result[iV] := Volts.mag;
                Inc(iV);
                Result[iV] := Volts.ang;
                Inc(iV);
            end;
    end
end;

procedure Bus_Get_VMagAngle_GR(); CDECL;
// Same as Bus_Get_VMagAngle but uses global result (GR) pointers
begin
    Bus_Get_VMagAngle(GR_DataPtr_PDouble, GR_CountPtr_PDouble)
end;

//------------------------------------------------------------------------------
function Bus_Get_TotalMiles(): Double; CDECL;
begin
    Result := 0.0;
    if ActiveCircuit <> NIL then
        with ActiveCircuit do
            if ActiveBusIndex > 0 then
                Result := Buses^[ActiveBusIndex].BusTotalMiles;
end;
//------------------------------------------------------------------------------
function Bus_Get_SectionID(): Integer; CDECL;
begin
    Result := 0;
    if ActiveCircuit <> NIL then
        with ActiveCircuit do
            if ActiveBusIndex > 0 then
                Result := Buses^[ActiveBusIndex].BusSectionID;
end;
//------------------------------------------------------------------------------
function Bus_Get_Next(): Integer; CDECL;
var
    BusIndex: Integer;
begin
    Result := -1;   // Signifies Error
    if ActiveCircuit <> NIL then
        with ActiveCircuit do
        begin
            BusIndex := ActiveBusIndex + 1;
            if (BusIndex > 0) and (BusIndex <= Numbuses) then
            begin
                ActiveBusIndex := BusIndex;
                Result := 0;
            end;
        end;
end;
//------------------------------------------------------------------------------
end.
