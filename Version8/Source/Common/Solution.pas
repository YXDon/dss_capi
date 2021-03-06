unit Solution;

{
  ----------------------------------------------------------
  Copyright (c) 2008-2015, Electric Power Research Institute, Inc.
  All rights reserved.
  ----------------------------------------------------------
}

{ Change Log
 8-14-99 Added progress display and abort on longer solution types
 11-3-99 added calc voltage base
 11-21-99 modified to  calc the voltage bases at the current load level set by the user.
 12-1-99 Added code to estimate starting point for P-V Generators
 12-2-99 Made more properties visible
 12-6-99 Merged properties with Set Command and removed from here
 12-15-99 Added global generatordispatchreference
 1-8-00   Fixed bug in autoadd generators to work with new generator model
          set vminpu=0 and vmaxpu=1000000
 1-30-00 to 2-1-00 Implemented control action check in solution
 2-19-00 Frequency changed reset to FALSE after being used (was causing all YPrims to be recomputed)
 2-23-00 Modified so that reset of meters and monitors is done upon setting the solution mode property.
         After that the user must reset else the monitors just accumulate.
 3-20-00 Fixed bug with setting generator disp reference - made uniform for all types
 6-11-00 Split into two modules + moved auto add stuff to AutoAdd
 9-20-00 Added Dynamic Mode
 10-25-00 Added Fundamental Freq and other stuff for Harmonics Solution
 5-30-01  Added control iterations check, mostIterationsdone.
          Fixed bug with controls off doing the solution too many times.

 8-14-01 Reset IntervalHrs on Mode change
 7-11-02 Added check for system Y change after computing currents

 9-28-03 Redefined V to NodeV and changed from an array from 1..n to 0..n where
         0-th element is alway ground(complex zero volts).
 8-14-06 Revised power flow initialization; removed forward/backward sweep

 9-14-16 Added SampleTheMeters Flag to allow sampling energy meters in Time and DutyCycle mode

}

interface

uses
    uCOMPLEX,
    Arraydef,
    Command,
    Monitor,
    DSSClass,
    DSSObject,
    Dynamics,
    EnergyMeter,
    VSource,
    SysUtils,
    Parallel_Lib,
{$IFDEF MSWINDOWS}
    Windows,
{$IFNDEF FPC}
    Dialogs,
{$ENDIF}
{$ELSE}
    BaseUnix,
    Unix,
{$ENDIF}
{$IFDEF FPC}
    Classes,
    Strings,
{$ELSE}
    System.Diagnostics,
    System.TimeSpan,
    System.Classes,
    {$ENDIF}
    Sparse_Math,
    SyncObjs,
    ExecHelper,
    CktElement;

const

    NORMALSOLVE = 0;
    NEWTONSOLVE = 1;
// Constants for the actor's messaging
    SIMULATE = 0;
    EXIT_ACTOR = 1;

    ALL_ACTORS = 0; // Wait flag for all the actors
    AD_ACTORS = 1; // Wait flag to wait only for the A-Diakoptics actors

type

    EControlProblem = class(Exception);
    ESolveError = class(Exception);  // Raised when solution aborted

    TNodeVarray = array[0..1000] of Complex;
    pNodeVarray = ^TNodeVarray;

    TDSSSolution = class(TDSSClass)


    PRIVATE
//       CommandList:TCommandlist;
    PROTECTED
        procedure DefineProperties;
    PUBLIC
        constructor Create;
        destructor Destroy; OVERRIDE;

        function Edit(ActorID: Integer): Integer; OVERRIDE;
        function Init(Handle: Integer; ActorID: Integer): Integer; OVERRIDE;
        function NewObject(const ObjName: String): Integer; OVERRIDE;

    end;

    TInfoMessageCall = procedure(const info: String) of object;  // Creates the procedure for sending a message

    TSolver = class(TThread)
        constructor Create(Susp: Boolean; local_CPU: Integer; ID: Integer; CallBack: TInfoMessageCall; AEvent: TEvent); OVERLOAD;
        procedure Execute; OVERRIDE;
        procedure Doterminate; OVERRIDE;
        destructor Destroy; OVERRIDE;

//*******************************Private components*****************************
    PROTECTED
        FMessage,
        Msg_Cmd: String;
        UINotifier,
        FInfoProc: TInfoMessageCall;
        ActorID,
        MsgType: Integer;
        UIEvent,
        ActorMsg: TEvent;
        AD_Init,          // used to know if the actors require a partial solution
        ActorActive,
        Processing: Boolean;

        procedure Start_Diakoptics();
        procedure Notify_Main;
        function Get_Processing(): Boolean;
        procedure Set_Processing(Nval: Boolean);
        function Get_CPU(): Integer;
        procedure Set_CPU(CPU: Integer);
//*******************************Public components******************************
    PUBLIC
        procedure Send_Message(Msg: Integer);
        procedure CallCallBack;
        property Event: TEvent READ UIEvent;

        property Is_Busy: Boolean READ Get_Processing WRITE Set_Processing;
        property CPU: Integer READ Get_CPU WRITE Set_CPU;

    end;

    TSolutionObj = class(TDSSObject)
    PRIVATE

        dV: pNodeVArray;   // Array of delta V for Newton iteration
        FFrequency: Double;

        function Converged(ActorID: Integer): Boolean;
        function OK_for_Dynamics(const Value: Integer): Boolean;
        function OK_for_Harmonics(const Value: Integer): Boolean;


        procedure DoNewtonSolution(ActorID: Integer);
        procedure DoNormalSolution(ActorID: Integer);
//       PROCEDURE GetMachineInjCurrents;
        procedure SetGeneratordQdV(ActorID: Integer);
        procedure SumAllCurrents(ActorID: Integer);
        procedure Set_Frequency(const Value: Double);
        procedure Set_Mode(const Value: Integer);
        procedure Set_Year(const Value: Integer);
        procedure Set_Total_Time(const Value: Double);

    PUBLIC

        Algorithm: Integer;      // NORMALSOLVE or NEWTONSOLVE
        AuxCurrents: pComplexArray;  // For injections like AutoAdd
        ControlActionsDone: Boolean;
        ControlIteration: Integer;
        ControlMode: Integer;     // EVENTDRIVEN, TIMEDRIVEN
        ConvergenceTolerance: Double;
        ConvergedFlag: Boolean;
        DefaultControlMode: Integer;    // EVENTDRIVEN, TIMEDRIVEN
        DefaultLoadModel: Integer;     // 1=POWERFLOW  2=ADMITTANCE
        DoAllHarmonics: Boolean;
        DynamicsAllowed: Boolean;
        DynaVars: TDynamicsRec;
        ErrorSaved: pDoubleArray;
        FirstIteration: Boolean;
        FrequencyChanged: Boolean;  // Flag set to true if something has altered the frequency
        Fyear: Integer;
        Harmonic: Double;
        HarmonicList: pDoubleArray;
        HarmonicListSize: Integer;
        hYsystem: NativeUint;   {Handle for main (system) Y matrix}
        hYseries: NativeUint;   {Handle for series Y matrix}
        hY: NativeUint;         {either hYsystem or hYseries}
        IntervalHrs: Double;   // Solution interval since last solution, hrs.
        IsDynamicModel: Boolean;
        IsHarmonicModel: Boolean;
        Iteration: Integer;
        LoadModel: Integer;        // 1=POWERFLOW  2=ADMITTANCE
        LastSolutionWasDirect: Boolean;
        LoadsNeedUpdating: Boolean;
        MaxControlIterations: Integer;
        MaxError: Double;
        MaxIterations,
        MinIterations: Integer;
        MostIterationsDone: Integer;
        NodeVbase: pDoubleArray;
        NumberOfTimes: Integer;  // Number of times to solve
        PreserveNodeVoltages: Boolean;
        RandomType: Integer;     //0 = none; 1 = gaussian; 2 = UNIFORM
        SampleTheMeters: Boolean;  // Flag to allow sampling of EnergyMeters
        SeriesYInvalid: Boolean;
        SolutionCount: Integer;  // Counter incremented for each solution
        SolutionInitialized: Boolean;
        SystemYChanged: Boolean;
        UseAuxCurrents: Boolean;
        VmagSaved: pDoubleArray;
        VoltageBaseChanged: Boolean;

       {Voltage and Current Arrays}
        NodeV: pNodeVArray;     // Main System Voltage Array   allows NodeV^[0]=0
        Currents: pNodeVArray;     // Main System Currents Array

       {A-Diakoptics variables}
        Node_dV: pNodeVArray;     // Used to store the partial solution voltage
        Ic_Local: pNodeVArray;     // Used to store the complementary curret

//******************************************************************************
        IncMat: Tsparse_matrix; // Incidence sparse matrix
        Laplacian: Tsparse_matrix; // Laplacian sparse matrix
//****************************Timing variables**********************************
        SolveStartTime: Int64;
        SolveEndtime: Int64;
        GStartTime: Int64;
        Gendtime: Int64;
        LoopEndtime: Int64;
        Total_Time_Elapsed: Double;
        Solve_Time_Elapsed: Double;
        Total_Solve_Time_Elapsed: Double;
        Step_Time_Elapsed: Double;
//******************************************************************************
// ActiveCell of the Incidence Matrix:
// [0] = row
// [1] = col
// [2] = value
        ActiveIncCell: array[0..2] of Integer;
//******************************************************************************
// IncMatrix Row and column descriptors
// Rows array (array of strings that tells what is the order of the PDElements)
// Columns array (array of strigns with the names of the cols of the Inc matrix)'
// Levels array (array of integers that describes the proximity level for each
// bus to the circuit's backbone)
        Inc_Mat_Rows: array of String;
        Inc_Mat_Cols: array of String;
        Inc_Mat_levels: array of Integer;
        temp_counter: Integer;
        Active_Cols: array of Integer;
        Active_Cols_Idx: array of Integer;
//******************************************************************************
//********************Diakoptics solution mode variables************************
        ADiakoptics_ready: Boolean;
        ADiakoptics_Actors: Integer;
//******************************************************************************
        constructor Create(ParClass: TDSSClass; const solutionname: String);
        destructor Destroy; OVERRIDE;

        procedure ZeroAuxCurrents(ActorID: Integer);
        function SolveZeroLoadSnapShot(ActorID: Integer): Integer;
        procedure DoPFLOWsolution(ActorID: Integer);

        procedure Solve(ActorID: Integer);                // Main Solution dispatch
        procedure SnapShotInit(ActorID: Integer);
        function SolveSnap(ActorID: Integer): Integer;    // solve for now once
        function SolveDirect(ActorID: Integer): Integer;  // solve for now once, direct solution
        function SolveYDirect(ActorID: Integer): Integer; // Similar to SolveDirect; used for initialization
        function SolveCircuit(ActorID: Integer): Integer; // SolveSnap sans control iteration
        procedure CheckControls(ActorID: Integer);       // Snapshot checks with matrix rebuild
        procedure SampleControlDevices(ActorID: Integer);
        procedure DoControlActions(ActorID: Integer);
        procedure Sample_DoControlActions(ActorID: Integer);    // Sample and Do
        procedure Check_Fault_Status(ActorID: Integer);

        procedure SetGeneratorDispRef(ActorID: Integer);
        procedure SetVoltageBases(ActorID: Integer);

        procedure SaveVoltages;
        procedure UpdateVBus(ActorID: Integer); // updates voltages for each bus    from NodeV
        procedure RestoreNodeVfromVbus;  // opposite   of updatebus

        function VDiff(i, j: Integer): Complex;  // Difference between two node voltages
        procedure InitPropertyValues(ArrayOffset: Integer); OVERRIDE;
        procedure DumpProperties(var F: TextFile; Complete: Boolean); OVERRIDE;
        procedure WriteConvergenceReport(const Fname: String);
        procedure Update_dblHour;
        procedure Increment_time;

        procedure UpdateLoopTime;

        property Mode: Integer READ dynavars.SolutionMode WRITE Set_Mode;
        property Frequency: Double READ FFrequency WRITE Set_Frequency;
        property Year: Integer READ FYear WRITE Set_Year;
        property Time_Solve: Double READ Solve_Time_Elapsed;
        property Time_TotalSolve: Double READ Total_Solve_Time_Elapsed;
        property Time_Step: Double READ Step_Time_Elapsed;     // Solve + sample
        property Total_Time: Double READ Total_Time_Elapsed WRITE Set_Total_Time;

 // Procedures that use to be private before 01-20-2016

        procedure AddInAuxCurrents(SolveType: Integer; ActorID: Integer);
        function SolveSystem(V: pNodeVArray; ActorID: Integer): Integer;
        procedure GetPCInjCurr(ActorID: Integer);
        procedure GetSourceInjCurrents(ActorID: Integer);
        procedure ZeroInjCurr(ActorID: Integer);
        procedure Upload2IncMatrix;

        procedure Calc_Inc_Matrix(ActorID: Integer);                // Calculates the incidence matrix for the Circuit
        procedure Calc_Inc_Matrix_Org(ActorID: Integer);            // Calculates the incidence matrix hierarchically organized for the Circuit

        function get_IncMatrix_Row(Col: Integer): Integer;          // Gets the index of the Row connected to the specified Column
        function get_IncMatrix_Col(Row: Integer): Integer;          // Gets the index of the Column connected to the specified Row
        function CheckLocationIdx(Idx: Integer): Integer;           // Evaluates the area covered by the tearing point to see if there is a better one

        procedure AddLines2IncMatrix(ActorID: Integer);             // Adds the Lines to the Incidence matrix arrays
        procedure AddXfmr2IncMatrix(ActorID: Integer);              // Adds the Xfmrs to the Incidence matrix arrays
        procedure AddSeriesCap2IncMatrix(ActorID: Integer);         // Adds capacitors in series to the Incidence matrix arrays
        procedure AddSeriesReac2IncMatrix(ActorID: Integer);        // Adds Reactors in series to the Incidence matrix arrays

    end;

{==========================================================================}

var
    ActiveSolutionObj: TSolutionObj;


implementation

uses
    SolutionAlgs,
    DSSClassDefs,
    DSSGlobals,
{$IFDEF FPC}
    CmdForms,
{$ELSE}
    DSSForms,
{$ENDIF}
    PDElement,
    ControlElem,
    Fault,
    Executive,
    AutoAdd,
    YMatrix,
    Load,
    CKtTree,
    ParserDel,
    Generator,
    Capacitor,
{$IFDEF MSWINDOWS}
    SHELLAPI,
{$ENDIF}
{$IFDEF DLL_ENGINE}
    ImplGlobals,  // to fire events
{$ENDIF}
    Math,
    Circuit,
    Utilities,
    KLUSolve,
{$IFNDEF FPC}
    ScriptEdit,
{$ENDIF}
    PointerList,
    Line,
    Transformer,
    Reactor,
    Diakoptics;

const
    NumPropsThisClass = 1;

{$DEFINE debugtrace}

{$UNDEF debugtrace}  {turn it off  delete this line to activate debug trace}

{$IFDEF debugtrace}
var
    FDebug: TextFile;

{$ENDIF}

// ===========================================================================================
constructor TDSSSolution.Create;  // Collection of all solution objects
begin
    inherited Create;
    Class_Name := 'Solution';
    DSSClassType := DSS_OBJECT + HIDDEN_ELEMENT;

    ActiveElement := 0;

    DefineProperties;

    CommandList := TCommandList.Create(Slice(PropertyName^, NumProperties));
    CommandList.Abbrev := TRUE;
end;

// ===========================================================================================
destructor TDSSSolution.Destroy;

begin
    // ElementList and  CommandList freed in inherited destroy
    inherited Destroy;

end;

// ===========================================================================================
procedure TDSSSolution.DefineProperties;
begin

    Numproperties := NumPropsThisClass;
    CountProperties;   // Get inherited property count
    AllocatePropertyArrays;


     // Define Property names
    PropertyName[1] := '-------';


     // define Property help values
    PropertyHelp[1] := 'Use Set Command to set Solution properties.';


    ActiveProperty := NumPropsThisClass;
    inherited DefineProperties;  // Add defs of inherited properties to bottom of list

end;


// ===========================================================================================
function TDSSSolution.NewObject(const ObjName: String): Integer;
begin
    // Make a new Solution Object and add it to Solution class list
    ActiveSolutionObj := TSolutionObj.Create(Self, ObjName);
    // this one is different than the rest of the objects.
    Result := AdDobjectToList(ActiveSolutionObj);
end;

// ===========================================================================================
constructor TSolutionObj.Create(ParClass: TDSSClass; const SolutionName: String);
// ===========================================================================================
begin
    inherited Create(ParClass);
    Name := LowerCase(SolutionName);

//    i := SetLogFile ('c:\\temp\\KLU_Log.txt', 1);

    FYear := 0;
    DynaVars.intHour := 0;
    DynaVars.t := 0.0;
    DynaVars.dblHour := 0.0;
    DynaVars.tstart := 0.0;
    DynaVars.tstop := 0.0;
    //duration := 0.0;
    DynaVars.h := 0.001;  // default for dynasolve

    LoadsNeedUpdating := TRUE;
    VoltageBaseChanged := TRUE;  // Forces Building of convergence check arrays

    MaxIterations := 15;
    MinIterations := 2;
    MaxControlIterations := 10;
    ConvergenceTolerance := 0.0001;
    ConvergedFlag := FALSE;

    SampleTheMeters := FALSE;  // Flag to tell solution algorithm to sample the Energymeters

    IsDynamicModel := FALSE;
    IsHarmonicModel := FALSE;

    Frequency := DefaultBaseFreq;
    {Fundamental := 60.0; Moved to Circuit and used as default base frequency}
    Harmonic := 1.0;

    FrequencyChanged := TRUE;  // Force Building of YPrim matrices
    DoAllHarmonics := TRUE;
    FirstIteration := TRUE;
    DynamicsAllowed := FALSE;
    SystemYChanged := TRUE;
    SeriesYInvalid := TRUE;

    {Define default harmonic list}
    HarmonicListSize := 5;
    HarmonicList := AllocMem(SizeOf(harmonicList^[1]) * HarmonicListSize);
    HarmonicList^[1] := 1.0;
    HarmonicList^[2] := 5.0;
    HarmonicList^[3] := 7.0;
    HarmonicList^[4] := 11.0;
    HarmonicList^[5] := 13.0;

    SolutionInitialized := FALSE;
    LoadModel := POWERFLOW;
    DefaultLoadModel := LoadModel;
    LastSolutionWasDirect := FALSE;

    hYseries := 0;
    hYsystem := 0;
    hY := 0;

    NodeV := NIL;
    dV := NIL;
    Currents := NIL;
    AuxCurrents := NIL;
    VMagSaved := NIL;
    ErrorSaved := NIL;
    NodeVbase := NIL;

    UseAuxCurrents := FALSE;

    SolutionCount := 0;

    Dynavars.SolutionMode := SNAPSHOT;
    ControlMode := CTRLSTATIC;
    DefaultControlMode := ControlMode;
    Algorithm := NORMALSOLVE;

    RandomType := GAUSSIAN;  // default to gaussian
    NumberOfTimes := 100;
    IntervalHrs := 1.0;

    InitPropertyValues(0);
    ADiakoptics_Ready := FALSE;   // A-Diakoptics needs to be initialized
    if not Assigned(ActorMA_Msg[ActiveActor]) then
        ActorMA_Msg[ActiveActor] := TEvent.Create(NIL, TRUE, FALSE, '');
end;

// ===========================================================================================
destructor TSolutionObj.Destroy;
begin

    Reallocmem(AuxCurrents, 0);
    Reallocmem(Currents, 0);
    Reallocmem(dV, 0);
    Reallocmem(ErrorSaved, 0);
    Reallocmem(NodeV, 0);
    Reallocmem(NodeVbase, 0);
    Reallocmem(VMagSaved, 0);

    if hYsystem <> 0 then
        DeleteSparseSet(hYsystem);
    if hYseries <> 0 then
        DeleteSparseSet(hYseries);
      {---------------------------}
//      SetLogFile ('c:\\temp\\KLU_Log.txt', 0);

    Reallocmem(HarmonicList, 0);
    ActorMA_Msg[ActiveActor].SetEvent;

// Sends a message to the working actor
    if ActorHandle[ActiveActor] <> NIL then
    begin
        ActorHandle[ActiveActor].Send_Message(EXIT_ACTOR);
        ActorHandle[ActiveActor].WaitFor;
        FreeandNil(ActorHandle[ActiveActor]);
    end;
    ActorMA_Msg[ActiveActor].Free;
    ActorMA_Msg[ActiveActor] := NIL;

    inherited Destroy;
end;


// ===========================================================================================
function TDSSSolution.Edit(ActorID: Integer): Integer;

begin
    Result := 0;

    ActiveSolutionObj := ActiveCircuit[ActorID].Solution;

    with ActiveSolutionObj do
    begin

       // This is all we do here now...
        Solve(ActorID);

    end;  {WITH}
end;

// ===========================================================================================
procedure TSolutionObj.Solve(ActorID: Integer);
{$IFNDEF FPC}
var
    ScriptEd: TScriptEdit;
{$ENDIF}
begin
    ActiveCircuit[ActorID].Issolved := FALSE;
    SolutionWasAttempted[ActorID] := TRUE;

{Check of some special conditions that must be met before executing solutions}

    if ActiveCircuit[ActorID].EmergMinVolts >= ActiveCircuit[ActorID].NormalMinVolts then
    begin
        DoSimpleMsg('Error: Emergency Min Voltage Must Be Less Than Normal Min Voltage!' +
            CRLF + 'Solution Not Executed.', 480);
        Exit;
    end;

    if SolutionAbort then
    begin
        GlobalResult := 'Solution aborted.';
        CmdResult := SOLUTION_ABORT;
        ErrorNumber := CmdResult;
        Exit;
    end;
    try
{Main solution Algorithm dispatcher}
        with ActiveCircuit[ActorID] do
        begin

            case Year of
                0:
                    DefaultGrowthFactor := 1.0;    // RCD 8-17-00
            else
                DefaultGrowthFactor := IntPower(DefaultGrowthRate, (year - 1));
            end;
        end;
{$IFDEF DLL_ENGINE}
        Fire_InitControls;
{$ENDIF}
    // Creates the actor again in case of being terminated due to an error before
        if ActorHandle[ActorID].Terminated or (ActorHandle[ActorID] = NIL) then
        begin
            if ActorHandle[ActorID].Terminated then
                ActorHandle[ActorID].Free;
            New_Actor(ActorID);
        end;
    {CheckFaultStatus;  ???? needed here??}


    // Resets the event for receiving messages from the active actor
      // Updates the status of the Actor in the GUI
        ActorStatus[ActorID] := 0;    // Global to indicate that the actor is busy
        ActorMA_Msg[ActorID].ResetEvent;
{$IFNDEF FPC}
        if not ADiakoptics then
        begin
            if not IsDLL then
                ScriptEd.UpdateSummaryForm('1');
        end
        else
        begin
            if ActorID = 1 then
                if not IsDLL then
                    ScriptEd.UpdateSummaryForm('1');
        end;
{$ENDIF}
      {$IFDEF MSWINDOWS}
        QueryPerformanceCounter(GStartTime);
{$ENDIF}

      // Sends message to start the Simulation
        ActorHandle[ActorID].Send_Message(SIMULATE);
      // If the parallel mode is not active, Waits until the actor finishes
        if not Parallel_enabled then
        begin
            Wait4Actors(ALL_ACTORS);
        {$IFNDEF FPC}
            if not ADiakoptics then
            begin
                if not IsDLL then
                    ScriptEd.UpdateSummaryForm('1');
            end
            else
            begin
                if ActorID = 1 then
                    if not IsDLL then
                        ScriptEd.UpdateSummaryForm('1');
            end;
        {$ENDIF}
        end;


    except

        On E: Exception do
        begin
            DoSimpleMsg('Error Encountered in Solve: ' + E.Message, 482);
            SolutionAbort := TRUE;
        end;

    end;

end;

// ===========================================================================================
function TSolutionObj.Converged(ActorID: Integer): Boolean;

var
    i: Integer;
    VMag: Double;
begin

// base convergence on voltage magnitude
    MaxError := 0.0;
    for i := 1 to ActiveCircuit[ActorID].NumNodes do
    begin

        VMag := Cabs(NodeV^[i]);

    { If base specified, use it; otherwise go on present magnitude  }
        if NodeVbase^[i] > 0.0 then
            ErrorSaved^[i] := Abs(Vmag - VmagSaved^[i]) / NodeVbase^[i]
        else
        if Vmag <> 0.0 then
            ErrorSaved^[i] := Abs(1.0 - VmagSaved^[i] / Vmag);

        VMagSaved^[i] := Vmag;  // for next go-'round

        MaxError := Max(MaxError, ErrorSaved^[i]);  // update max error

    end;


{$IFDEF debugtrace}
    Assignfile(Fdebug, 'Debugtrace.csv');
    Append(FDebug);
    if Iteration = 1 then
    begin
        Write(Fdebug, 'Iter');
        for i := 1 to ActiveCircuit[ActorID].NumNodes do
            Write(Fdebug, ', ', ActiveCircuit[ActorID].Buslist.get(ActiveCircuit[ActorID].MapNodeToBus^[i].BusRef), '.', ActiveCircuit[ActiveActor].MapNodeToBus^[i].NodeNum: 0);
        Writeln(Fdebug);
    end;
              {*****}
    Write(Fdebug, Iteration: 2);
    for i := 1 to ActiveCircuit[ActorID].NumNodes do
        Write(Fdebug, ', ', VMagSaved^[i]: 8: 1);
    Writeln(Fdebug);
    Write(Fdebug, 'Err');
    for i := 1 to ActiveCircuit[ActorID].NumNodes do
        Write(Fdebug, ', ', Format('%-.5g', [ErrorSaved^[i]]));
    Writeln(Fdebug);
    Write(Fdebug, 'Curr');
    for i := 1 to ActiveCircuit[ActorID].NumNodes do
        Write(Fdebug, ', ', Cabs(Currents^[i]): 8: 1);
    Writeln(Fdebug);
              {*****}
    CloseFile(FDebug);
{$ENDIF}
    ;

    if (MaxError <= ConvergenceTolerance) and (not IsNaN(MaxError)) then
        Result := TRUE
    else
        Result := FALSE;


    ConvergedFlag := Result;
end;


// ===========================================================================================
procedure TSolutionObj.GetSourceInjCurrents(ActorID: Integer);

// Add in the contributions of all source type elements to the global solution vector InjCurr

var
    pElem: TDSSCktElement;

begin

    with ActiveCircuit[ActorID] do
    begin

        pElem := Sources.First;
        while pElem <> NIL do
        begin
            if pElem.Enabled then
                pElem.InjCurrents(ActorID); // uses NodeRef to add current into InjCurr Array;
            pElem := Sources.Next;
        end;

    end;

end;

// ===========================================================================================
procedure TSolutionObj.SetGeneratorDispRef(ActorID: Integer);

// Set the global generator dispatch reference

begin
    with ActiveCircuit[ActorID] do
        case Dynavars.SolutionMode of

            SNAPSHOT:
                GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor;
            YEARLYMODE:
                GeneratorDispatchReference := DefaultGrowthFactor * DefaultHourMult.re;
            DAILYMODE:
                GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
            DUTYCYCLE:
                GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
            GENERALTIME:
                GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
            DYNAMICMODE:
                GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor;
            HARMONICMODE:
                GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor;
            MONTECARLO1:
                GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor;
            MONTECARLO2:
                GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
            MONTECARLO3:
                GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
            PEAKDAY:
                GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
            LOADDURATION1:
                GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
            LOADDURATION2:
                GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
            DIRECT:
                GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor;
            MONTEFAULT:
                GeneratorDispatchReference := 1.0;  // Monte Carlo Fault Cases solve  at peak load only base case
            FAULTSTUDY:
                GeneratorDispatchReference := 1.0;
            AUTOADDFLAG:
                GeneratorDispatchReference := DefaultGrowthFactor;   // peak load only
            HARMONICMODET:
                GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
        else
            DosimpleMsg('Unknown solution mode.', 483);
        end;
end;
// ===========================================================================================
procedure TSolutionObj.SetGeneratordQdV(ActorID: Integer);

var
    pGen: TGeneratorObj;
    Did_One: Boolean;
    GenDispSave: Double;

begin
    Did_One := FALSE;

     // Save the generator dispatch level and set on high enough to
     // turn all generators on
    GenDispSave := ActiveCircuit[ActorID].GeneratorDispatchReference;
    ActiveCircuit[ActorID].GeneratorDispatchReference := 1000.0;

    with ActiveCircuit[ActorID] do
    begin

        pGen := Generators.First;
        while pGen <> NIL do
        begin

            if pGen.Enabled then
            begin

              // for PV generator models only ...
                if pGen.genModel = 3 then
                begin

                    pGen.InitDQDVCalc;

                   // solve at base var setting
                    Iteration := 0;
                    repeat
                        Inc(Iteration);
                        ZeroInjCurr(ActorID);
                        GetSourceInjCurrents(ActorID);
                        pGen.InjCurrents(ActorID);   // get generator currents with nominal vars
                        SolveSystem(NodeV, ActorID);
                    until Converged(ActorID) or (Iteration >= Maxiterations);

                    pGen.RememberQV(ActorID);  // Remember Q and V
                    pGen.BumpUpQ;

                   // solve after changing vars
                    Iteration := 0;
                    repeat
                        Inc(Iteration);
                        ZeroInjCurr(ActorID);
                        GetSourceInjCurrents(ActorID);
                        pGen.InjCurrents(ActorID);   // get generator currents with nominal vars
                        SolveSystem(NodeV, ActorID);
                    until Converged(ActorID) or (Iteration >= Maxiterations);

                    pGen.CalcdQdV(ActorID); // bssed on remembered Q and V and present values of same
                    pGen.ResetStartPoint;

                    Did_One := TRUE;
                end;
            end;
            pGen := Generators.Next;
        end;

    end;

     // Restore generator dispatch reference
    ActiveCircuit[ActorID].GeneratorDispatchReference := GenDispSave;
    try
        if Did_One        // Reset Initial Solution
        then
            SolveZeroLoadSnapShot(ActorID);
    except
        ON E: EEsolv32Problem do
        begin
            DoSimpleMsg('From SetGenerator DQDV, SolveZeroLoadSnapShot: ' + CRLF + E.Message + CheckYMatrixforZeroes(ActorID), 7071);
            raise ESolveError.Create('Aborting');
        end;
    end;

end;

// ===========================================================================================
procedure TSolutionObj.DoNormalSolution(ActorID: Integer);

{ Normal fixed-point solution

   Vn+1 = [Y]-1 Injcurr

   Where Injcurr includes only PC elements  (loads, generators, etc.)
   i.e., the shunt elements.

   Injcurr are the current injected INTO the NODE
        (need to reverse current direction for loads)
}

begin


    Iteration := 0;

 {**** Main iteration loop ****}
    with ActiveCircuit[ActorID] do
        repeat
            Inc(Iteration);

            if LogEvents then
                LogThisEvent('Solution Iteration ' + IntToStr(Iteration), ActorID);

    { Get injcurrents for all PC devices  }
            ZeroInjCurr(ActorID);
            GetSourceInjCurrents(ActorID);  // sources
            GetPCInjCurr(ActorID);  // Get the injection currents from all the power conversion devices and feeders

       // The above call could change the primitive Y matrix, so have to check
            if SystemYChanged then
            begin
                BuildYMatrix(WHOLEMATRIX, FALSE, ActorID);  // Does not realloc V, I
            end;

            if UseAuxCurrents then
                AddInAuxCurrents(NORMALSOLVE, ActorID);

      // Solve for voltages                      {Note:NodeV[0] = 0 + j0 always}
            if LogEvents then
                LogThisEvent('Solve Sparse Set DoNormalSolution ...', ActorID);
            SolveSystem(NodeV, ActorID);
            LoadsNeedUpdating := FALSE;

        until (Converged(ActorID) and (Iteration >= MinIterations)) or (Iteration >= MaxIterations);

end;


// ===========================================================================================
procedure TSolutionObj.DoNewtonSolution(ActorID: Integer);

{ Newton Iteration

   Vn+1 =  Vn - [Y]-1 Termcurr

   Where Termcurr includes currents from all elements and we are
   attempting to get the  currents to sum to zero at all nodes.

   Termcurr is the sum of all currents going INTO THE TERMINALS of
   the elements.

   For PD Elements, Termcurr = Yprim*V

   For Loads, Termcurr = (Sload/V)*
   For Generators, Termcurr = -(Sgen/V)*

}

var
    i: Integer;

begin

    with ActiveCircuit[ActorID] do
    begin
        ReAllocMem(dV, SizeOf(dV^[1]) * (NumNodes + 1)); // Make sure this is always big enough

        if ControlIteration = 1 then
            GetPCInjCurr(ActorID);  // Update the load multipliers for this solution

        Iteration := 0;
        repeat
            Inc(Iteration);
            Inc(SolutionCount);    // SumAllCurrents Uses ITerminal  So must force a recalc

        // Get sum of currents at all nodes for all  devices
            ZeroInjCurr(ActorID);
            SumAllCurrents(ActorID);

           // Call to current calc could change YPrim for some devices
            if SystemYChanged then
            begin
                BuildYMatrix(WHOLEMATRIX, FALSE, ActorID);   // Does not realloc V, I
            end;

            if UseAuxCurrents then
                AddInAuxCurrents(NEWTONSOLVE, ActorID);

        // Solve for change in voltages
            SolveSystem(dV, ActorID);

            LoadsNeedUpdating := FALSE;

         // Compute new guess at voltages
            for i := 1 to NumNodes do     // 0 node is always 0
                with NodeV^[i] do
                begin
                    re := re - dV^[i].re;
                    im := im - dV^[i].im;
                end;

        until (Converged(ActorID) and (Iteration >= MinIterations)) or (Iteration >= MaxIterations);
    end;
end;


// ===========================================================================================
procedure TSolutionObj.DoPFLOWsolution(ActorID: Integer);


begin

    Inc(SolutionCount);    //Unique number for this solution

    if VoltageBaseChanged then
        InitializeNodeVbase(ActorID); // for convergence test

    if not SolutionInitialized then
    begin

        if ActiveCircuit[ActorID].LogEvents then
            LogThisEvent('Initializing Solution', ActorID);
        try
        //SolveZeroLoadSnapShot;
            SolveYDirect(ActorID);  // 8-14-06 This should give a better answer than zero load snapshot
        except
            ON E: EEsolv32Problem do
            begin
                DoSimpleMsg('From DoPFLOWsolution.SolveYDirect: ' + CRLF + E.Message + CheckYMatrixforZeroes(ActorID), 7072);
                raise ESolveError.Create('Aborting');
            end;
        end;
        if SolutionAbort then
            Exit; // Initialization can result in abort

        try
            SetGeneratordQdV(ActorID);  // Set dQdV for Model 3 generators
        except
            ON E: EEsolv32Problem do
            begin
                DoSimpleMsg('From DoPFLOWsolution.SetGeneratordQdV: ' + CRLF + E.Message + CheckYMatrixforZeroes(ActorID), 7073);
                raise ESolveError.Create('Aborting');
            end;
        end;

        { The above resets the active sparse set to hY }
        SolutionInitialized := TRUE;
    end;


    case Algorithm of
        NORMALSOLVE:
            DoNormalSolution(ActorID);
        NEWTONSOLVE:
            DoNewtonSolution(ActorID);
    end;

    ActiveCircuit[ActorID].Issolved := ConvergedFlag;
    LastSolutionWasDirect := FALSE;

end;

// ===========================================================================================
function TSolutionObj.SolveZeroLoadSnapShot(ActorID: Integer): Integer;

// Solve without load for initialization purposes;

begin
    Result := 0;

    if SystemYChanged or SeriesYInvalid then
    begin
        BuildYMatrix(SERIESONLY, TRUE, ActorID);   // Side Effect: Allocates V
    end;
    Inc(SolutionCount);    //Unique number for this solution

    ZeroInjCurr(ActorID);   // Side Effect: Allocates InjCurr
    GetSourceInjCurrents(ActorID);    // Vsource, Isource and VCCS only

    {Make the series Y matrix the active matrix}
    if hYseries = 0 then
        raise EEsolv32Problem.Create('Series Y matrix not built yet in SolveZeroLoadSnapshot.');
    hY := hYseries;

    if ActiveCircuit[ActiveActor].LogEvents then
        LogThisEvent('Solve Sparse Set ZeroLoadSnapshot ...', ActorID);

    SolveSystem(NodeV, ActorID);  // also sets voltages in radial part of the circuit if radial solution

    { Reset the main system Y as the solution matrix}
    if (hYsystem > 0) and not SolutionAbort then
        hY := hYsystem;
end;

// ===========================================================================================
procedure TSolutionObj.SetVoltageBases(ActorID: Integer);

// Set voltage bases using voltage at first node (phase) of a bus

var
    i: Integer;
    bZoneCalc, bZoneLock: Boolean;

begin

    try
    // don't allow the meter zones to auto-build in this load flow solution, because the
    // voltage bases are not available yet

        bZoneCalc := ActiveCircuit[ActorID].MeterZonesComputed;
        bZoneLock := ActiveCircuit[ActorID].ZonesLocked;
        ActiveCircuit[ActorID].MeterZonesComputed := TRUE;
        ActiveCircuit[ActorID].ZonesLocked := TRUE;

        SolveZeroLoadSnapShot(ActorID);

        with ActiveCircuit[ActorID] do
            for i := 1 to NumBuses do
                with Buses^[i] do
                    kVBase := NearestBasekV(Cabs(NodeV^[GetRef(1)]) * 0.001732) / SQRT3;  // l-n base kV

        InitializeNodeVbase(ActorID);      // for convergence test

        ActiveCircuit[ActorID].Issolved := TRUE;

    // now build the meter zones
        ActiveCircuit[ActorID].MeterZonesComputed := bZoneCalc;
        ActiveCircuit[ActorID].ZonesLocked := bZoneLock;
        ActiveCircuit[ActorID].DoResetMeterZones(ActorID);

    except
        ON E: EEsolv32Problem do
        begin
            DoSimpleMsg('From SetVoltageBases.SolveZeroLoadSnapShot: ' + CRLF + E.Message + CheckYMatrixforZeroes(ActorID), 7075);
            raise ESolveError.Create('Aborting');
        end;
    end;

end;

procedure TSolutionObj.SnapShotInit(ActorID: Integer);

begin

    SetGeneratorDispRef(ActorID);
    ControlIteration := 0;
    ControlActionsDone := FALSE;
    MostIterationsDone := 0;
    LoadsNeedUpdating := TRUE;  // Force the loads to update at least once

end;

procedure TSolutionObj.CheckControls(ActorID: Integer);

begin
    if ControlIteration < MaxControlIterations then
    begin
        if ConvergedFlag then
        begin
            if ActiveCircuit[ActorID].LogEvents then
                LogThisEvent('Control Iteration ' + IntToStr(ControlIteration), ActorID);
            Sample_DoControlActions(ActorID);
            Check_Fault_Status(ActorID);
        end
        else
            ControlActionsDone := TRUE; // Stop solution process if failure to converge
    end;

    if SystemYChanged then
    begin
        BuildYMatrix(WHOLEMATRIX, FALSE, ActorID); // Rebuild Y matrix, but V stays same
    end;
end;

// ===========================================================================================
function TSolutionObj.SolveSnap(ActorID: Integer): Integer;  // solve for now once

var
    TotalIterations: Integer;

begin
//      if Solution then
    SnapShotInit(ActorID);
    TotalIterations := 0;
  {$IFDEF MSWINDOWS}
    QueryPerformanceCounter(SolveStartTime);
   {$ENDIF}
    repeat

        Inc(ControlIteration);

        Result := SolveCircuit(ActorID);  // Do circuit solution w/o checking controls
       {Now Check controls}
{$IFDEF DLL_ENGINE}
        Fire_CheckControls;
{$ENDIF}
        CheckControls(ActorID);

       {For reporting max iterations per control iteration}
        if Iteration > MostIterationsDone then
            MostIterationsDone := Iteration;

        TotalIterations := TotalIterations + Iteration;

    until ControlActionsDone or (ControlIteration >= MaxControlIterations);

    if not ControlActionsDone and (ControlIteration >= MaxControlIterations) then
    begin
        DoSimpleMsg('Warning Max Control Iterations Exceeded. ' + CRLF + 'Tip: Show Eventlog to debug control settings.', 485);
        SolutionAbort := TRUE;   // this will stop this message in dynamic power flow modes
    end;

    if ActiveCircuit[ActorID].LogEvents then
        LogThisEvent('Solution Done', ActorID);

{$IFDEF DLL_ENGINE}
    Fire_StepControls;
{$ENDIF}
  {$IFDEF MSWINDOWS}
    QueryPerformanceCounter(SolveEndtime);
   {$ENDIF}
    Solve_Time_Elapsed := ((SolveEndtime - SolveStartTime) / CPU_Freq) * 1000000;
    Iteration := TotalIterations;  { so that it reports a more interesting number }

end;

// ===========================================================================================
function TSolutionObj.SolveDirect(ActorID: Integer): Integer;  // solve for now once, direct solution

begin
    Result := 0;

    LoadsNeedUpdating := TRUE;  // Force possible update of loads and generators
   {$IFDEF MSWINDOWS}
    QueryPerformanceCounter(SolveStartTime);
   {$ELSE}
    SolveStartTime := GetTickCount64;
   {$ENDIF}

    if SystemYChanged then
    begin
        BuildYMatrix(WHOLEMATRIX, TRUE, ActorID);   // Side Effect: Allocates V
    end;

    Inc(SolutionCount);   // Unique number for this solution

    ZeroInjCurr(ActorID);   // Side Effect: Allocates InjCurr
    GetSourceInjCurrents(ActorID);

   // Pick up PCELEMENT injections for Harmonics mode and Dynamics mode
   // Ignore these injections for powerflow; Use only admittance in Y matrix
    if IsDynamicModel or IsHarmonicModel then
        GetPCInjCurr(ActorID);

    if SolveSystem(NodeV, ActorID) = 1   // Solve with Zero injection current
    then
    begin
        ActiveCircuit[ActorID].IsSolved := TRUE;
        ConvergedFlag := TRUE;
    end;
  {$IFDEF MSWINDOWS}
    QueryPerformanceCounter(SolveEndtime);
   {$ENDIF}
    Solve_Time_Elapsed := ((SolveEndtime - SolveStartTime) / CPU_Freq) * 1000000;
    Total_Time_Elapsed := Total_Time_Elapsed + Solve_Time_Elapsed;
    Iteration := 1;
    LastSolutionWasDirect := TRUE;

end;


function TSolutionObj.SolveCircuit(ActorID: Integer): Integer;
begin
    Result := 0;
    if LoadModel = ADMITTANCE then
        try
            SolveDirect(ActorID)     // no sense horsing around when it's all admittance
        except
            ON E: EEsolv32Problem do
            begin
                DoSimpleMsg('From SolveSnap.SolveDirect: ' + CRLF + E.Message + CheckYMatrixforZeroes(ActorID), 7075);
                raise ESolveError.Create('Aborting');
            end;
        end
    else
    begin
        try
            if SystemYChanged then
            begin
                BuildYMatrix(WHOLEMATRIX, TRUE, ActorID);   // Side Effect: Allocates V
            end;

            DoPFLOWsolution(ActorID);
        except
            ON E: EEsolv32Problem do
            begin
                DoSimpleMsg('From SolveSnap.DoPflowSolution: ' + CRLF + E.Message + CheckYMatrixforZeroes(ActorID), 7074);
                raise ESolveError.Create('Aborting');
            end;
        end
    end;

end;

// ===========================================================================================
procedure TSolutionObj.ZeroInjCurr(ActorID: Integer);
var
    I: Integer;
begin
    for i := 0 to ActiveCircuit[ActorID].NumNodes do
        Currents^[i] := CZERO;
end;
// ===========================================================================================
procedure TSolutionObj.Upload2IncMatrix;
var
    CIdx: Integer;

begin
  // Uploads the values to the incidence matrix
    IncMat.insert((ActiveIncCell[0] - 1), (ActiveIncCell[1] - 2), ActiveIncCell[2]);
    ActiveIncCell[2] := -1;
end;
// ===========================================================================================
procedure TSolutionObj.AddLines2IncMatrix(ActorID: Integer);
var
    LineBus: String;
    elem: TLineObj;
    TermIdx,
    CIdx,
    BusdotIdx: Integer;
    EndFlag: Boolean;
    counter: Integer;
begin
// This rouitne adds the Lines to the incidence matrix vectors
    with ActiveCircuit[ActorID] do
    begin
        elem := Lines.First;
//    Counter     :=  0;
        while elem <> NIL do
        begin
            if elem.Enabled then
            begin
                ActiveIncCell[2] := 1;
                inc(temp_counter);
                setlength(Inc_Mat_Rows, temp_counter);
                Inc_Mat_Rows[temp_counter - 1] := 'Line.' + elem.Name;
                for TermIdx := 1 to 2 do
                begin
                    LineBus := elem.GetBus(TermIdx);
                    BusdotIdx := ansipos('.', LineBus);
                    if BusdotIdx <> 0 then
                        LineBus := Copy(LineBus, 0, BusdotIdx - 1);  // removes the dot from the Bus Name
            // Evaluates the position of the Bus in the array
                    ActiveIncCell[1] := 1;
                    EndFlag := TRUE;
                    while (ActiveIncCell[1] <= NumBuses) and (EndFlag) do
                    begin
                        if LineBus = BusList.Get(ActiveIncCell[1]) then
                            EndFlag := FALSE;
                        ActiveIncCell[1] := ActiveIncCell[1] + 1;
                    end;
                    Upload2IncMatrix;
//            inc(Counter);
                end;
                inc(ActiveIncCell[0]);
            end
            else
            begin
                Counter := 0;
            end;
            elem := Lines.Next;
        end;
//    Counter :=  Counter;
    end;
end;
// ===========================================================================================
procedure TSolutionObj.AddXfmr2IncMatrix(ActorID: Integer);
var
    LineBus: String;
    elem: TTransfObj;
    TermIdx,
    BusdotIdx,
    CIdx: Integer;
    EndFlag: Boolean;
    lst: TPointerList;
    Counter: Integer;

begin
// This rouitne adds the Transformers to the incidence matrix vectors
    with ActiveCircuit[ActorID] do
    begin
        lst := ActiveCircuit[ActorID].Transformers;
        elem := lst.First;
        while elem <> NIL do
        begin
            if elem.Enabled then
            begin
                ActiveIncCell[2] := 1;
                inc(temp_counter);
                setlength(Inc_Mat_Rows, temp_counter);
                Inc_Mat_Rows[temp_counter - 1] := 'Transformer.' + elem.Name;
                for TermIdx := 1 to elem.NumberOfWindings do
                begin
                    LineBus := elem.GetBus(TermIdx);
                    BusdotIdx := ansipos('.', LineBus);
                    if BusdotIdx <> 0 then
                        LineBus := Copy(LineBus, 0, BusdotIdx - 1);  // removes the dot from the Bus Name
            // Evaluates the position of the Bus in the array
                    ActiveIncCell[1] := 1;
                    EndFlag := TRUE;
                    while (ActiveIncCell[1] <= NumBuses) and (EndFlag) do
                    begin
                        if LineBus = BusList.Get(ActiveIncCell[1]) then
                            EndFlag := FALSE;
                        ActiveIncCell[1] := ActiveIncCell[1] + 1;
                    end;
                    Upload2IncMatrix;
                end;
                inc(ActiveIncCell[0]);
            end;
            elem := lst.Next;
        end;
    end;
end;
// ===========================================================================================
procedure TSolutionObj.AddSeriesCap2IncMatrix(ActorID: Integer);
var
    CapBus: String;
    elem: TCapacitorObj;
    lst: TPointerList;
    CapTermIdx,
    BusdotIdx,
    CIdx: Integer;
    CapEndFlag: Boolean;
begin
// This rouitne adds the series capacitors to the incidence matrix vectors
    with ActiveCircuit[ActorID] do
    begin
        lst := ShuntCapacitors;
        elem := lst.First;
        while elem <> NIL do
        begin
            if elem.NumTerminals > 1 then
            begin
                if elem.Enabled then
                begin
                    inc(temp_counter);
                    setlength(Inc_Mat_Rows, temp_counter);
                    Inc_Mat_Rows[temp_counter - 1] := 'Capacitor.' + elem.Name;
                    ActiveIncCell[2] := 1;
                    for CapTermIdx := 1 to 2 do
                    begin
                        CapBus := elem.GetBus(CapTermIdx);
                        BusdotIdx := ansipos('.', CapBus);
                        if BusdotIdx <> 0 then
                            CapBus := Copy(CapBus, 0, BusdotIdx - 1);  // removes the dot from the Bus Name
            // Evaluates the position of the Bus in the array
                        ActiveIncCell[1] := 1;
                        CapEndFlag := TRUE;
                        while (ActiveIncCell[1] <= NumBuses) and (CapEndFlag) do
                        begin
                            if CapBus = BusList.Get(ActiveIncCell[1]) then
                                CapEndFlag := FALSE;
                            ActiveIncCell[1] := ActiveIncCell[1] + 1;
                        end;
                        Upload2IncMatrix;
                    end;
                    inc(ActiveIncCell[0]);
                end;
            end;
            elem := lst.Next;
        end;
    end;
end;
// ===========================================================================================
procedure TSolutionObj.AddSeriesReac2IncMatrix(ActorID: Integer);
var
    RBus: String;
    elem,
    DevClassIndex: Integer;
    TermIdx,
    BusdotIdx,
    CIdx: Integer;
    EndFlag: Boolean;
begin
// This rouitne adds the series reactors to the incidence matrix vectors
    with ActiveCircuit[ActorID] do
    begin
        DevClassIndex := ClassNames[ActorID].Find('reactor');
        LastClassReferenced[ActorID] := DevClassIndex;
        ActiveDSSClass[ActorID] := DSSClassList[ActorID].Get(LastClassReferenced[ActorID]);
        elem := ActiveDSSClass[ActorID].First;
        while elem <> 0 do
        begin
            RBus := ActiveCktElement.GetBus(2);
            BusdotIdx := ansipos('.0', RBus);
            if BusdotIdx = 0 then
            begin
                inc(temp_counter);
                setlength(Inc_Mat_Rows, temp_counter);
                Inc_Mat_Rows[temp_counter - 1] := 'Reactor.' + ActiveCktElement.Name;
                ActiveIncCell[2] := 1;
                for TermIdx := 1 to 2 do
                begin
                    RBus := ActiveCktElement.GetBus(TermIdx);
                    BusdotIdx := ansipos('.', RBus);
                    if BusdotIdx <> 0 then
                        RBus := Copy(RBus, 0, BusdotIdx - 1);  // removes the dot from the Bus Name
          // Evaluates the position of the Bus in the array
                    ActiveIncCell[1] := 1;
                    EndFlag := TRUE;
                    while (ActiveIncCell[1] <= NumBuses) and (EndFlag) do
                    begin
                        if RBus = BusList.Get(ActiveIncCell[1]) then
                            EndFlag := FALSE;
                        ActiveIncCell[1] := ActiveIncCell[1] + 1;
                    end;
                    Upload2IncMatrix;
                end;
            end;
            elem := ActiveDSSClass[ActorID].Next;
            inc(ActiveIncCell[0]);
        end;
    end;
end;
//*********Routine for extracting the Branch to Node incidence matrix***********
//*     The order depends on the way the lines, xfmr, series cap and reactors  *
//******************************************************************************
procedure TSolutionObj.Calc_Inc_Matrix(ActorID: Integer);
var
    dlong: Integer;
begin
  // If the sparse matrix obj doesn't exists creates it, otherwise deletes the content
    if IncMat = NIL then
        IncMat := Tsparse_matrix.Create
    else
        IncMat.reset;

    if ActiveCircuit[ActorID] <> NIL then
        with ActiveCircuit[ActorID] do
        begin
            temp_counter := 0;
            ActiveIncCell[0] := 1;           // Activates row 1 of the incidence matrix
      // Now we proceed to evaluate the link branches
            AddLines2IncMatrix(ActorID);      // Includes the Lines
            AddXfmr2IncMatrix(ActorID);       // Includes the Xfmrs
            AddSeriesCap2IncMatrix(ActorID);  // Includes Series Cap
            AddSeriesReac2IncMatrix(ActorID); // Includes Series Reactors
            IncMat_Ordered := FALSE;
        end;
end;

{*******************************************************************************
* This function delivers the Row index connected to the Column at the input    *
*                   Inside the B2N incidence Matrix                            *
********************************************************************************}
function TSolutionObj.get_IncMatrix_Row(Col: Integer): Integer;
var
    Tflag: Boolean;
    idx_1: Integer;
begin
    Result := -1;
    Tflag := TRUE;
    for idx_1 := 1 to (IncMat.NZero - 1) do    //Looks for the Column in the IncMatrix
    begin
        if (IncMat.data[idx_1][1] = Col) and Tflag then
        begin
            Result := IncMat.data[idx_1][0];
            Tflag := FALSE;
        end;
    end;
end;

{*******************************************************************************
* This function delivers the Column index connected to the Row at the input    *
*                   Inside the B2N incidence Matrix                            *
********************************************************************************}
function TSolutionObj.get_IncMatrix_Col(Row: Integer): Integer;
var
    Tflag: Boolean;
    Idx_1: Integer;
begin
    Result := -1;
    Tflag := TRUE;    // Detection Flag
    for Idx_1 := 1 to (IncMat.NZero - 1) do    //Looks for the row in the IncMatrix
    begin
        if (IncMat.data[Idx_1][0] = Row) and Tflag then
        begin
            setlength(Active_Cols, 2);
            setlength(Active_Cols_Idx, 2);
            Active_Cols[0] := IncMat.data[Idx_1][1];     //Stores the indexes of both columns for the link branch
            Active_Cols[1] := IncMat.data[Idx_1 + 1][1]; //In case they need to be used in the future by the caller
            Active_Cols_Idx[0] := IncMat.data[Idx_1 - 1][2]; //Stores the indexes of both columns for the link branch
            Active_Cols_Idx[1] := IncMat.data[Idx_1][2];     //In case they need to be used in the future by the caller
            Result := IncMat.data[Idx_1][1];
            Tflag := FALSE;
        end;
    end;
end;

//*********Routine for extracting the Branch to Node incidence matrix***********
//*     Organized hierarchically. This routine also calculates the             *
//*     Levels vector for defining the proximity of the bus to the circuit's   *
//*     Backbone. To do it, this routine uses the CktTree class                *
//******************************************************************************
procedure TSolutionObj.Calc_Inc_Matrix_Org(ActorID: Integer);

var
//  Ftree       : TextFile;                           // For debugging
    pdElem: TPDElement;
    topo: TCktTree;
//  TreeNm,                                           // For debugging
//  FileRoot,                                         // For debugging
    PDE_Name: String;                            // Name of the PDElement
    PDE_Buses: array of String;                   // Buses of the PDElement
    Temp_Array: array of Integer;                  // Local Shared variable
    nLevels,                                            // Current number of levels for the active Bus
    i,                                                  // Default counter
    j,                                                  // Default counter
    j2,                                                 // Default counter
    ZeroLevel,                                          // Number of Zero level Buses
    BusdotIdx,
    row,
    col,
    val,                                          // Local Shared variable
    nPDE: Integer;                           // PDElements index
begin
    try
        if ActiveCircuit[ActorID] <> NIL then
        begin
//      TreeNm := FileRoot + 'TopoTree_Cols.csv';   // For debuging
            topo := ActiveCircuit[ActiveActor].GetTopology;
            nLevels := 0;
            nPDE := 0;
            setlength(Inc_Mat_Cols, 0);
      //Init the spaser matrix
            if IncMat = NIL then
                IncMat := Tsparse_matrix.Create
            else
                IncMat.reset;

            ActiveIncCell[0] := -1;           // Activates row 1 of the incidence matrix
            if Assigned(topo) then
            begin
                PDElem := topo.First;
                while Assigned(PDElem) do
                begin
                    nLevels := topo.Level;
                    PDE_Name := PDElem.ParentClass.Name + '.' + PDElem.Name;
//******************Gets the buses to which the PDE is connected****************
                    with ActiveCircuit[ActorID] do
                    begin
                        ActiveCircuit[ActorID].SetElementActive(PDE_Name);
                        SetLength(PDE_Buses, ActiveCktElement.Nterms);
                        for i := 1 to ActiveCktElement.Nterms do
                        begin
                            PDE_Buses[i - 1] := ActiveCktElement.GetBus(i);
                            BusdotIdx := ansipos('.', PDE_Buses[i - 1]);
                            if BusdotIdx <> 0 then
                                PDE_Buses[i - 1] := Copy(PDE_Buses[i - 1], 0, BusdotIdx - 1);  // removes the dot from the Bus Name
                        end;
                        if length(Inc_Mat_Cols) = 0 then  //First iteration so the Cols array will be loaded
                        begin
                            setlength(Inc_Mat_Cols, 1);
                            setlength(Inc_Mat_Levels, 1);
                            Inc_Mat_Cols[0] := PDE_Buses[0];
                            Inc_Mat_levels[0] := nLevels;
                        end
                        else                               //The Cols array is populated with something
                        begin
                            inc(nPDE);
                            setlength(Inc_Mat_Rows, nPDE);
                            Inc_Mat_Rows[nPDE - 1] := PDE_Name;
                            for j := 0 to ActiveCktElement.Nterms - 1 do
                            begin
                                row := ActiveIncCell[0];                 //Sets the row
                                BusdotIdx := -1;               // Flag to not create a new variable
                                for i := 0 to length(Inc_Mat_Cols) - 1 do   // Checks if the bus already exists in the Cols array
                                    if Inc_Mat_Cols[i] = PDE_Buses[j] then
                                        BusdotIdx := i;
                                if BusdotIdx >= 0 then
                                    col := BusdotIdx   //Sets the Col
                                else
                                begin
                                    setlength(Inc_Mat_Cols, length(Inc_Mat_Cols) + 1);
                                    setlength(Inc_Mat_levels, length(Inc_Mat_levels) + 1);
                                    Inc_Mat_Cols[length(Inc_Mat_Cols) - 1] := PDE_Buses[j];
                                    Inc_Mat_levels[length(Inc_Mat_Cols) - 1] := nLevels;
                                    col := length(Inc_Mat_Cols) - 1; //Sets the Col
                                end;
                                if j = 0 then
                                    val := 1 //Sets the value
                                else
                                    val := -1;
                                IncMat.insert(row, col, val);
                            end;
                        end;
                    end;
                    inc(ActiveIncCell[0]);
                    PDElem := topo.GoForward;
                end;
            end;
{*******************************************************************************
*   Now the levels array needs to be reprocessed to get the 0 level buses,     *
*   they are on a continuous path from the feeder head to the feeder end       *
********************************************************************************}
            BusdotIdx := MaxIntValue(Inc_Mat_levels);
            for i := 0 to length(Inc_Mat_levels) do
                if Inc_Mat_levels[i] = BusdotIdx then
                    nLevels := i;
            for j := 1 to BusdotIdx - 1 do
            begin
                for i := 0 to nLevels do
                begin
                    if Inc_Mat_levels[i] = j then
                        ZeroLevel := i;
                end;
                Inc_Mat_levels[ZeroLevel] := 0;
            end;
//**********Normalize the branches of the level between zero level buses********
            BusdotIdx := 0;
            j := 0;
            ZeroLevel := 0;
            SetLength(Temp_Array, 0);
            for i := 0 to high(Inc_Mat_levels) do
            begin
                if (Inc_Mat_levels[i] = 0) then
                begin
                    if length(Temp_Array) > 0 then    // The array subset is large enough for
                    begin                             //Normalizing it
                        BusdotIdx := MinIntValue(Temp_Array) - 1;
                        for j2 := ZeroLevel to (length(Temp_Array) + ZeroLevel - 1) do
                            Inc_Mat_levels[j2] := Inc_Mat_levels[j2] - BusdotIdx;
                        SetLength(Temp_Array, 0);
                    end;
                    ZeroLevel := i + 1;
                end
                else
                begin
                    setlength(Temp_Array, (length(Temp_Array) + 1));
                    Temp_Array[High(Temp_Array)] := Inc_Mat_levels[i];
                end;
            end;
//************Verifies is something else was missing at the end*****************
            if (ZeroLevel < (length(Inc_Mat_levels) - 1)) then
            begin
                BusdotIdx := 0;                                                // Counter for defining the level
                j := 0;                                                // Stores the previous value (shift reg)
                for j2 := ZeroLevel to High(Inc_Mat_levels) do
                begin
                    if Inc_Mat_levels[j2] >= j then
                        inc(BusdotIdx)
                    else
                    begin
                        ActiveIncCell[1] := get_IncMatrix_Row(j2);                //Looks for the Column in the IncMatrix
                        if ActiveIncCell[1] < 0 then                                //Checks if the col was located (just in case)
                            BusdotIdx := 1
                        else
                        begin
                            ActiveIncCell[2] := get_IncMatrix_Col(ActiveIncCell[1]);  //Looks for the row in the IncMatrix
                            if Active_Cols[0] = j2 then
                                BusdotIdx := Inc_Mat_levels[Active_Cols[1]] + 1
                            else
                                BusdotIdx := Inc_Mat_levels[ActiveIncCell[2]] + 1;
                        end;
                    end;
                    j := Inc_Mat_levels[j2];
                    Inc_Mat_levels[j2] := BusdotIdx;
                end;
            end;
            IncMat_Ordered := TRUE;
        end;
    finally

    end;
end;

{*******************************************************************************
*           Routine created to empty a recently created folder                 *
********************************************************************************}
{$IFDEF MSWINDOWS}
procedure DelFilesFromDir(Directory, FileMask: String; DelSubDirs: Boolean);
var
    SourceLst: String;
    FOS: TSHFileOpStruct;
begin
    FillChar(FOS, SizeOf(FOS), 0);
    FOS.wFunc := FO_DELETE;
    SourceLst := Directory + PathDelim + FileMask + #0;
    FOS.pFrom := Pchar(SourceLst);
    if not DelSubDirs then
        FOS.fFlags := FOS.fFlags or FOF_FILESONLY;
  // Remove the next line if you want a confirmation dialog box
    FOS.fFlags := FOS.fFlags or FOF_NOCONFIRMATION;
  // Add the next line for a "silent operation" (no progress box)
    FOS.fFlags := FOS.fFlags or FOF_SILENT;
    SHFileOperation(FOS);
end;

{$ENDIF}
{$IFDEF UNIX}
procedure DeltreeDir(Directory: String);
var
    Info: TSearchRec;
begin
    if FindFirst(Directory + PathDelim + '*', faAnyFile and faDirectory, Info) = 0 then
    begin
        repeat
            with Info do
            begin
                if (name = '.') or (name = '..') then
                    continue;
                if (Attr and faDirectory) = faDirectory then
                begin
                    DeltreeDir(Directory + PathDelim + Name)
                end
                else
                begin
                    DeleteFile(Directory + PathDelim + Name);
                end;
            end;
        until FindNext(info) <> 0;
    end;
    rmdir(Directory);
end;

procedure DelFilesFromDir(Directory, FileMask: String; DelSubDirs: Boolean);
var
    Info: TSearchRec;
    flags: Longint;
begin
    if DelSubDirs then
        flags := faAnyFile and faDirectory
    else
        flags := faAnyFile;

    if FindFirst(Directory + PathDelim + FileMask, flags, Info) = 0 then
    begin
        repeat
            with Info do
            begin
                if (name = '.') or (name = '..') then
                    continue;
                if (Attr and faDirectory) = faDirectory then
                begin
                    try
                        DeltreeDir(Directory + PathDelim + Name)
                    except
                        Writeln('Could not remove directory ' + Directory + PathDelim + Name);
                    end;
                end
                else
                begin
                    DeleteFile(Directory + PathDelim + Name);
                end;
            end;
        until FindNext(info) <> 0;
    end;
end;

{$ENDIF}

{*******************************************************************************
*   This routine evaluates if the current location is the best or if its       *
*   Necessary to move back one PDE just to cover a wider area                  *
********************************************************************************}
function TSolutionObj.CheckLocationIdx(Idx: Integer): Integer;
begin
    if Inc_Mat_Levels[Idx - 1] = 0 then
        Result := idx - 1
    else
        Result := idx;
end;

//----------------------------------------------------------------------------
function TDSSSolution.Init(Handle: Integer; ActorID: Integer): Integer;

begin
    DoSimpleMsg('Need to implement TSolution.Init', -1);
    Result := 0;
end;


// ===========================================================================================
procedure TSolutionObj.GetPCInjCurr(ActorID: Integer);
var
    pElem: TDSSCktElement;

{ Get inj currents from all enabled PC devices }

begin

    with ActiveCircuit[ActorID] do
    begin
        pElem := PCElements.First;
        while pElem <> NIL do
        begin
            with pElem do
                if Enabled then
                    InjCurrents(ActorID); // uses NodeRef to add current into InjCurr Array;
            pElem := PCElements.Next;
        end;
    end;

end;

procedure TSolutionObj.DumpProperties(var F: TextFile; complete: Boolean);

var
    i, j: Integer;

   // for dumping the matrix in compressed columns
    p: Longword;
    hY: NativeUInt;
    nBus, nNZ: Longword;
    ColPtr, RowIdx: array of Longword;
    cVals: array of Complex;
begin

    Writeln(F, '! OPTIONS');

  // Inherited DumpProperties(F,Complete);

    Writeln(F, '! NumNodes = ', ActiveCircuit[ActiveActor].NumNodes: 0);

    {WITH ParentClass Do
     FOR i := 1 to NumProperties Do
     Begin
        Writeln(F,'Set ',PropertyName^[i],'=',PropertyValue^[i]);
     End;
     }
    Writeln(F, 'Set Mode=', GetSolutionModeID);
    Writeln(F, 'Set ControlMode=', GetControlModeID);
    Writeln(F, 'Set Random=', GetRandomModeID);
    Writeln(F, 'Set hour=', DynaVars.intHour: 0);
    Writeln(F, 'Set sec=', Format('%-g', [DynaVars.t]));
    Writeln(F, 'Set year=', Year: 0);
    Writeln(F, 'Set frequency=', Format('%-g', [Frequency]));
    Writeln(F, 'Set stepsize=', Format('%-g', [DynaVars.h]));
    Writeln(F, 'Set number=', NumberOfTimes: 0);
    Writeln(F, 'Set circuit=', ActiveCircuit[ActiveActor].Name);
    Writeln(F, 'Set editor=', DefaultEditor);
    Writeln(F, 'Set tolerance=', Format('%-g', [ConvergenceTolerance]));
    Writeln(F, 'Set maxiterations=', MaxIterations: 0);
    Writeln(F, 'Set miniterations=', MinIterations: 0);
    Writeln(F, 'Set loadmodel=', GetLoadModel);

    Writeln(F, 'Set loadmult=', Format('%-g', [ActiveCircuit[ActiveActor].LoadMultiplier]));
    Writeln(F, 'Set Normvminpu=', Format('%-g', [ActiveCircuit[ActiveActor].NormalMinVolts]));
    Writeln(F, 'Set Normvmaxpu=', Format('%-g', [ActiveCircuit[ActiveActor].NormalMaxVolts]));
    Writeln(F, 'Set Emergvminpu=', Format('%-g', [ActiveCircuit[ActiveActor].EmergMinVolts]));
    Writeln(F, 'Set Emergvmaxpu=', Format('%-g', [ActiveCircuit[ActiveActor].EmergMaxVolts]));
    Writeln(F, 'Set %mean=', Format('%-.4g', [ActiveCircuit[ActiveActor].DefaultDailyShapeObj.Mean * 100.0]));
    Writeln(F, 'Set %stddev=', Format('%-.4g', [ActiveCircuit[ActiveActor].DefaultDailyShapeObj.StdDev * 100.0]));
    Writeln(F, 'Set LDCurve=', ActiveCircuit[ActiveActor].LoadDurCurve);  // Load Duration Curve
    Writeln(F, 'Set %growth=', Format('%-.4g', [((ActiveCircuit[ActiveActor].DefaultGrowthRate - 1.0) * 100.0)]));  // default growth rate
    with ActiveCircuit[ActiveActor].AutoAddObj do
    begin
        Writeln(F, 'Set genkw=', Format('%-g', [GenkW]));
        Writeln(F, 'Set genpf=', Format('%-g', [GenPF]));
        Writeln(F, 'Set capkvar=', Format('%-g', [Capkvar]));
        Write(F, 'Set addtype=');
        case Addtype of
            GENADD:
                Writeln(F, 'generator');
            CAPADD:
                Writeln(F, 'capacitor');
        end;
    end;
    Write(F, 'Set allowduplicates=');
    if ActiveCircuit[ActiveActor].DuplicatesAllowed then
        Writeln(F, 'Yes')
    else
        Writeln(F, 'No');
    Write(F, 'Set zonelock=');
    if ActiveCircuit[ActiveActor].ZonesLocked then
        Writeln(F, 'Yes')
    else
        Writeln(F, 'No');
    Writeln(F, 'Set ueweight=', ActiveCircuit[ActiveActor].UEWeight: 8: 2);
    Writeln(F, 'Set lossweight=', ActiveCircuit[ActiveActor].LossWeight: 8: 2);
    Writeln(F, 'Set ueregs=', IntArraytoString(ActiveCircuit[ActiveActor].UEregs, ActiveCircuit[ActiveActor].NumUERegs));
    Writeln(F, 'Set lossregs=', IntArraytoString(ActiveCircuit[ActiveActor].Lossregs, ActiveCircuit[ActiveActor].NumLossRegs));
    Write(F, 'Set voltagebases=(');  //  changes the default voltage base rules
    i := 1;
    with ActiveCircuit[ActiveActor] do
        while LegalVoltageBases^[i] > 0.0 do
        begin
            Write(F, LegalVoltageBases^[i]: 10: 2);
            inc(i);
        end;
    Writeln(F, ')');
    case Algorithm of
        NORMALSOLVE:
            Writeln(F, 'Set algorithm=normal');
        NEWTONSOLVE:
            Writeln(F, 'Set algorithm=newton');
    end;
    Write(F, 'Set Trapezoidal=');
    if ActiveCircuit[ActiveActor].TrapezoidalIntegration then
        Writeln(F, 'yes')
    else
        Writeln(F, 'no');
    Writeln(F, 'Set genmult=', Format('%-g', [ActiveCircuit[ActiveActor].GenMultiplier]));

    Writeln(F, 'Set Basefrequency=', Format('%-g', [ActiveCircuit[ActiveActor].Fundamental]));

    Write(F, 'Set harmonics=(');  //  changes the default voltage base rules
    if DoAllHarmonics then
        Write(F, 'ALL')
    else
        for i := 1 to HarmonicListSize do
            Write(F, Format('%-g, ', [HarmonicList^[i]]));
    Writeln(F, ')');
    Writeln(F, 'Set maxcontroliter=', MaxControlIterations: 0);
    Writeln(F);

    if Complete then
        with ActiveCircuit[ActiveActor] do
        begin

            hY := Solution.hY;

      // get the compressed columns out of KLU
            FactorSparseMatrix(hY); // no extra work if already done
            GetNNZ(hY, @nNZ);
            GetSize(hY, @nBus);
            SetLength(ColPtr, nBus + 1);
            SetLength(RowIdx, nNZ);
            SetLength(cVals, nNZ);
            GetCompressedMatrix(hY, nBus + 1, nNZ, @ColPtr[0], @RowIdx[0], @cVals[0]);

            Writeln(F, 'System Y Matrix (Lower Triangle by Columns)');
            Writeln(F);
            Writeln(F, '  Row  Col               G               B');
            Writeln(F);

      // traverse the compressed column format
            for j := 0 to nBus - 1 do
            begin /// the zero-based column
                for p := ColPtr[j] to ColPtr[j + 1] - 1 do
                begin
                    i := RowIdx[p];  // the zero-based row
                    Writeln(F, Format('[%4d,%4d] = %12.5g + j%12.5g', [i + 1, j + 1, cVals[p].re, cVals[p].im]));
                end;
            end;
        end;
end;

function TSolutionObj.VDiff(i, j: Integer): Complex;

begin
    Result := Csub(NodeV^[i], NodeV^[j]);  // V1-V2
end;


procedure TSolutionObj.WriteConvergenceReport(const Fname: String);
var
    i: Integer;
    F: TextFile;
begin
    try
        Assignfile(F, Fname);
        ReWrite(F);

        Writeln(F);
        Writeln(F, '-------------------');
        Writeln(F, 'Convergence Report:');
        Writeln(F, '-------------------');
        Writeln(F, '"Bus.Node", "Error", "|V|","Vbase"');
        with ActiveCircuit[ActiveActor] do
            for i := 1 to NumNodes do
                with MapNodeToBus^[i] do
                begin
                    Write(F, '"', pad((BusList.Get(Busref) + '.' + IntToStr(NodeNum) + '"'), 18));
                    Write(F, ', ', ErrorSaved^[i]: 10: 5);
                    Write(F, ', ', VmagSaved^[i]: 14);
                    Write(F, ', ', NodeVbase^[i]: 14);
                    Writeln(F);
                end;

        Writeln(F);
        Writeln(F, 'Max Error = ', MaxError: 10: 5);

    finally

        CloseFile(F);
        FireOffEditor(Fname);

    end;

end;

// =========================================================================================== =
procedure TSolutionObj.SumAllCurrents(ActorID: Integer);

var
    pelem: TDSSCktElement;

begin
    with  ActiveCircuit[ActorID] do
    begin
        pelem := CktElements.First;
        while pelem <> NIL do
        begin
            pelem.SumCurrents(ActorID);   // sum terminal currents into system Currents Array
            pelem := CktElements.Next;
        end;
    end;
end;

// =========================================================================================== =
procedure TSolutionObj.DoControlActions(ActorID: Integer);
var
    XHour: Integer;
    XSec: Double;
begin
    with ActiveCircuit[ActorID] do
    begin
        case ControlMode of

            CTRLSTATIC:
            begin  //  execute the nearest set of control actions but leaves time where it is
                if ControlQueue.IsEmpty then
                    ControlActionsDone := TRUE
                else
                    ControlQueue.DoNearestActions(xHour, XSec, ActorID); // ignore time advancement
            end;
            EVENTDRIVEN:
            begin  //  execute the nearest set of control actions and advance time to that time
                 // **** Need to update this to set the "Intervalhrs" variable for EnergyMeters for Event-Driven Simulation ****
                if not ControlQueue.DoNearestActions(DynaVars.intHour, DynaVars.t, ActorID) // these arguments are var type
                then
                    ControlActionsDone := TRUE;// Advances time to the next event
            end;
            TIMEDRIVEN:
            begin   // Do all actions having an action time <= specified time
                if not ControlQueue.DoActions(DynaVars.intHour, DynaVars.t, ActorID) then
                    ControlActionsDone := TRUE;
            end;
            MULTIRATE:
            begin  //  execute the nearest set of control actions but leaves time where it is
                if not ControlQueue.DoMultiRate(DynaVars.intHour, DynaVars.t, ActorID) then
                    ControlActionsDone := TRUE;
            end;
        end;
    end;

end;

// =========================================================================================== =
procedure TSolutionObj.SampleControlDevices(ActorID: Integer);

var
    ControlDevice: TControlElem;

begin
    with ActiveCircuit[ActorID] do
    begin
        ControlDevice := NIL;
        try
            // Sample all controls and set action times in control Queue
            ControlDevice := DSSControls.First;
            while ControlDevice <> NIL do
            begin
                if ControlDevice.Enabled then
                    ControlDevice.Sample(ActorID);
                ControlDevice := DSSControls.Next;
            end;

        except
            On E: Exception do
            begin
                DoSimpleMsg(Format('Error Sampling Control Device "%s.%s" %s  Error = %s', [ControlDevice.ParentClass.Name, ControlDevice.Name, CRLF, E.message]), 484);
                raise EControlProblem.Create('Solution aborted.');
            end;
        end;
    end;

end;

// =========================================================================================== =
procedure TSolutionObj.Sample_DoControlActions(ActorID: Integer);


begin

    if ControlMode = CONTROLSOFF then
        ControlActionsDone := TRUE
    else
    begin

        SampleControlDevices(ActorID);
        DoControlActions(ActorID);

     {This variable lets control devices know the bus list has changed}
        ActiveCircuit[ActorID].Control_BusNameRedefined := FALSE;  // Reset until next change
    end;

end;

procedure TSolutionObj.Set_Mode(const Value: Integer);


begin

    DynaVars.intHour := 0;
    DynaVars.t := 0.0;
    Update_dblHour;
    ActiveCircuit[ActiveActor].TrapezoidalIntegration := FALSE;

    if not OK_for_Dynamics(Value) then
        Exit;
    if not OK_for_Harmonics(Value) then
        Exit;

    Dynavars.SolutionMode := Value;

    ControlMode := DefaultControlMode;   // Revert to default mode
    LoadModel := DefaultLoadModel;

    IsDynamicModel := FALSE;
    IsHarmonicModel := FALSE;

    SolutionInitialized := FALSE;   // reinitialize solution when mode set (except dynamics)
    PreserveNodeVoltages := FALSE;  // don't do this unless we have to
    SampleTheMeters := FALSE;
   // Reset defaults for solution modes
    case Dynavars.SolutionMode of

        PEAKDAY,
        DAILYMODE:
        begin
            DynaVars.h := 3600.0;
            NumberOfTimes := 24;
            SampleTheMeters := TRUE;
        end;
        SNAPSHOT:
        begin
            IntervalHrs := 1.0;
            NumberOfTimes := 1;
        end;
        YEARLYMODE:
        begin
            IntervalHrs := 1.0;
            DynaVars.h := 3600.0;
            NumberOfTimes := 8760;
            SampleTheMeters := TRUE;
        end;
        DUTYCYCLE:
        begin
            DynaVars.h := 1.0;
            ControlMode := TIMEDRIVEN;
        end;
        DYNAMICMODE:
        begin
            DynaVars.h := 0.001;
            ControlMode := TIMEDRIVEN;
            IsDynamicModel := TRUE;
            PreserveNodeVoltages := TRUE;  // need to do this in case Y changes during this mode
        end;
        GENERALTIME:
        begin
            IntervalHrs := 1.0;
            DynaVars.h := 3600.0;
            NumberOfTimes := 1;  // just one time step per Solve call expected
        end;
        MONTECARLO1:
        begin
            IntervalHrs := 1.0;
            SampleTheMeters := TRUE;
        end;
        MONTECARLO2:
        begin
            DynaVars.h := 3600.0;
            SampleTheMeters := TRUE;
        end;
        MONTECARLO3:
        begin
            IntervalHrs := 1.0;
            SampleTheMeters := TRUE;
        end;
        MONTEFAULT:
        begin
            IsDynamicModel := TRUE;
        end;
        FAULTSTUDY:
        begin
            IsDynamicModel := TRUE;
        end;
        LOADDURATION1:
        begin
            DynaVars.h := 3600.0;
            ActiveCircuit[ActiveActor].TrapezoidalIntegration := TRUE;
            SampleTheMeters := TRUE;
        end;
        LOADDURATION2:
        begin
            DynaVars.intHour := 1;
            ActiveCircuit[ActiveActor].TrapezoidalIntegration := TRUE;
            SampleTheMeters := TRUE;
        end;
        AUTOADDFLAG:
        begin
            IntervalHrs := 1.0;
            ActiveCircuit[ActiveActor].AutoAddObj.ModeChanged := TRUE;
        end;
        HARMONICMODE:
        begin
            ControlMode := CONTROLSOFF;
            IsHarmonicModel := TRUE;
            LoadModel := ADMITTANCE;
            PreserveNodeVoltages := TRUE;  // need to do this in case Y changes during this mode
        end;
        HARMONICMODET:
        begin
            IntervalHrs := 1.0;
            DynaVars.h := 3600.0;
            NumberOfTimes := 1;
            ControlMode := CONTROLSOFF;
            IsHarmonicModel := TRUE;
            LoadModel := ADMITTANCE;
            PreserveNodeVoltages := TRUE;  // need to do this in case Y changes during this mode
        end;
    end;

   {Moved here 9-8-2007 so that mode is changed before reseting monitors, etc.}

   // Reset Meters and Monitors
    MonitorClass[ActiveActor].ResetAll(ActiveActor);
    EnergyMeterClass[ActiveActor].ResetAll(ActiveActor);
    DoResetFaults;
    DoResetControls;

end;

procedure TSolutionObj.AddInAuxCurrents(SolveType: Integer; ActorID: Integer);

begin
    {FOR i := 1 to ActiveCircuit[ActiveActor].NumNodes Do Caccum(Currents^[i], AuxCurrents^[i]);}
    // For Now, only AutoAdd Obj uses this

    if Dynavars.SolutionMode = AUTOADDFLAG then
        ActiveCircuit[ActorID].AutoAddObj.AddCurrents(SolveType, ActorID);

end;

procedure TSolutionObj.ZeroAuxCurrents(ActorID: Integer);
var
    i: Integer;
begin
    for i := 1 to ActiveCircuit[ActiveActor].NumNodes do
        AuxCurrents^[i] := CZERO;
end;

procedure TSolutionObj.Check_Fault_Status(ActorID: Integer);

var
    pFault: TFaultOBj;

begin
    with ActiveCircuit[ActorID] do
    begin

        pFault := TFaultObj(Faults.First);
        while pFault <> NIL do
        begin
            pFault.CheckStatus(ControlMode, ActorID);
            pFault := TFaultObj(Faults.Next);
        end;

    end;  {End With}
end;


{ This procedure is called for Solve Direct and any other solution method
  that does not get the injection currents for PC elements normally. In Dynamics mode,
  Generators are voltage sources ...

Procedure TSolutionObj.GetMachineInjCurrents;

Var
  pElem:TDSSCktElement;

begin
     // do machines in Dynamics Mode
     IF   IsDynamicModel THEN
      With ActiveCircuit[ActiveActor] DO  Begin

         pElem := Generators.First;
         WHILE pElem<>nil Do Begin
             IF pElem.Enabled THEN pElem.InjCurrents; // uses NodeRef to add current into InjCurr Array;
             pElem := Generators.Next;
         End;

       End;

end;
}

function TSolutionObj.OK_for_Dynamics(const Value: Integer): Boolean;

var
    ValueIsDynamic: Boolean;

begin

    Result := TRUE;

    case Value of
        MONTEFAULT,
        DYNAMICMODE,
        FAULTSTUDY:
            ValueIsDynamic := TRUE;
    else
        ValueIsDynamic := FALSE;
    end;

   {When we go in and out of Dynamics mode, we have to do some special things}
    if IsDynamicModel and not ValueIsDynamic then
        InvalidateAllPCELEMENTS;  // Force Recomp of YPrims when we leave Dynamics mode

    if not IsDynamicModel and ValueIsDynamic then
    begin   // see if conditions right for going into dynamics

        if ActiveCircuit[ActiveActor].IsSolved then
            CalcInitialMachineStates   // set state variables for machines (loads and generators)
        else
        begin
           {Raise Error Message if not solved}
            DoSimpleMsg('Circuit must be solved in a non-dynamic mode before entering Dynamics or Fault study modes!' + CRLF +
                'If you attempted to solve, then the solution has not yet converged.', 486);
            if In_ReDirect then
                Redirect_Abort := TRUE;  // Get outta here
            Result := FALSE;
        end;
    end;

end;

function TSolutionObj.OK_for_Harmonics(const Value: Integer): Boolean;

 {When we go in and out of Harmonics mode, we have to do some special things}
begin

    Result := TRUE;

    if IsHarmonicModel and not ((Value = HARMONICMODE) or (Value = HARMONICMODET)) then
    begin
        InvalidateAllPCELEMENTS;  // Force Recomp of YPrims when we leave Harmonics mode
        Frequency := ActiveCircuit[ActiveActor].Fundamental;   // Resets everything to norm
    end;

    if not IsHarmonicModel and ((Value = HARMONICMODE) or (Value = HARMONICMODET)) then
    begin   // see if conditions right for going into Harmonics

        if (ActiveCircuit[ActiveActor].IsSolved) and (Frequency = ActiveCircuit[ActiveActor].Fundamental) then
        begin
            if not InitializeForHarmonics(ActiveActor)   // set state variables for machines (loads and generators) and sources
            then
            begin
                Result := FALSE;
                if In_ReDirect then
                    Redirect_Abort := TRUE;  // Get outta here
            end;
        end
        else
        begin

            DoSimpleMsg('Circuit must be solved in a fundamental frequency power flow or direct mode before entering Harmonics mode!', 487);
            if In_ReDirect then
                Redirect_Abort := TRUE;  // Get outta here
            Result := FALSE;
        end;
    end;

end;

procedure TSolutionObj.Set_Frequency(const Value: Double);
begin
    if FFrequency <> Value then
    begin
        FrequencyChanged := TRUE;  // Force Rebuild of all Y Primitives
        SystemYChanged := TRUE;  // Force rebuild of System Y
    end;

    FFrequency := Value;
    if ActiveCircuit[ActiveActor] <> NIL then
        Harmonic := FFrequency / ActiveCircuit[ActiveActor].Fundamental;  // Make Sure Harmonic stays in synch
end;

procedure TSolutionObj.Increment_time;
begin
    with Dynavars do
    begin
        t := t + h;
        while t >= 3600.0 do
        begin
            Inc(intHour);
            t := t - 3600.0;
        end;
        Update_dblHour;
    end;
end;

procedure TSolutionObj.InitPropertyValues(ArrayOffset: Integer);
begin

    PropertyValue[1] := '';

    inherited InitPropertyValues(NumPropsThisClass);

end;

procedure TSolutionObj.Set_Year(const Value: Integer);
begin
    if DIFilesAreOpen[ActiveActor] then
        EnergyMeterClass[ActiveActor].CloseAllDIFiles(ActiveActor);
    FYear := Value;
    DynaVars.intHour := 0;  {Change year, start over}
    Dynavars.t := 0.0;
    Update_dblHour;
    EnergyMeterClass[ActiveActor].ResetAll(ActiveActor);  // force any previous year data to complete
end;

procedure TSolutionObj.Set_Total_Time(const Value: Double);
begin
    Total_Time_Elapsed := Value;
end;

procedure TSolutionObj.SaveVoltages;

var
    F: TextFile;
    Volts: Complex;
    i, j: Integer;
    BusName: String;

begin

    try

        try
            AssignFile(F, CircuitName_[ActiveActor] + 'SavedVoltages.Txt');
            Rewrite(F);

            with ActiveCircuit[ActiveActor] do
                for i := 1 to NumBuses do
                begin
                    BusName := BusList.Get(i);
                    for j := 1 to Buses^[i].NumNodesThisBus do
                    begin
                        Volts := NodeV^[Buses^[i].GetRef(j)];
                        Writeln(F, BusName, ', ', Buses^[i].GetNum(j): 0, Format(', %-.7g, %-.7g', [Cabs(Volts), CDang(Volts)]));
                    end;
                end;

        except
            On E: Exception do
            begin
                DoSimpleMsg('Error opening Saved Voltages File: ' + E.message, 488);
                Exit;
            end;
        end;


    finally

        CloseFile(F);
        GlobalResult := CircuitName_[ActiveActor] + 'SavedVoltages.Txt';

    end;

end;

{  *************  MAIN SOLVER CALL  ************************}

function TSolutionObj.SolveSystem(V: pNodeVArray; ActorID: Integer): Integer;

var
    RetCode: Integer;
    iRes: Longword;
    dRes: Double;

begin

 {Note: NodeV[0] = 0 + j0 always.  Therefore, pass the address of the element 1 of the array.
 }
    try
    // new function to log KLUSolve.DLL function calls; same information as stepping through in Delphi debugger
    // SetLogFile ('KLU_Log.txt', 1);
        RetCode := SolveSparseSet(hY, @V^[1], @Currents^[1]);  // Solve for present InjCurr
{$IFDEF DSS_CAPI}
        if (DSS_CAPI_INFO_SPARSE_COND) then // Disabled by default with DSS C-API
        begin
{$ENDIF}
    // new information functions
            GetFlops(hY, @dRes);
            GetRGrowth(hY, @dRes);
            GetRCond(hY, @dRes);
    // GetCondEst (hY, @dRes); // this can be expensive
{$IFDEF DSS_CAPI}
        end;
{$ENDIF}
        GetSize(hY, @iRes);
        GetNNZ(hY, @iRes);
        GetSparseNNZ(hY, @iRes);
        GetSingularCol(hY, @iRes);
    except
        On E: Exception do
            raise  EEsolv32Problem.Create('Error Solving System Y Matrix.  Sparse matrix solver reports numerical error: ' + E.Message);
    end;

    Result := RetCode;

end;

procedure TSolutionObj.Update_dblHour;
begin
    DynaVars.dblHour := DynaVars.intHour + dynavars.t / 3600.0;
end;

procedure TSolutionObj.UpdateLoopTime;
begin

// Update Loop time is called from end of time step cleanup
// Timer is based on beginning of SolveSnap time

   {$IFDEF MSWINDOWS}
    QueryPerformanceCounter(LoopEndTime);
{$ENDIF}
    Step_Time_Elapsed := ((LoopEndtime - SolveStartTime) / CPU_Freq) * 1000000;

end;

procedure TSolutionObj.UpdateVBus(ActorID: Integer);

// Save present solution vector values to buses
var
    i, j: Integer;
begin
    with ActiveCircuit[ActorID] do
    begin
        for i := 1 to NumBuses do
            with Buses^[i] do
                if Assigned(Vbus) then
                    for j := 1 to NumNodesThisBus do
                        VBus^[j] := NodeV^[GetRef(j)];
    end;
end;

procedure TSolutionObj.RestoreNodeVfromVbus;
var
    i, j: Integer;
begin
    with ActiveCircuit[ActiveActor] do
        for i := 1 to NumBuses do
            with Buses^[i] do
                if Assigned(Vbus) then
                    for j := 1 to NumNodesThisBus do
                        NodeV^[GetRef(j)] := VBus^[j];

end;

function TSolutionObj.SolveYDirect(ActorID: Integer): Integer;

{ Solves present Y matrix with no injection sources except voltage and current sources }

begin

    Result := 0;

    ZeroInjCurr(ActorID);   // Side Effect: Allocates InjCurr
    GetSourceInjCurrents(ActorID);
    if IsDynamicModel then
        GetPCInjCurr(ActorID);  // Need this in dynamics mode to pick up additional injections

    SolveSystem(NodeV, ActorID); // Solve with Zero injection current

end;

{*******************************************************************************
*             Used to create the OpenDSS Solver thread                         *
********************************************************************************
}

constructor TSolver.Create(Susp: Boolean; local_CPU: Integer; ID: Integer; CallBack: TInfoMessageCall; AEvent: TEvent);

var
    Parallel: TParallel_Lib;
    Thpriority: String;
begin


    UIEvent := AEvent;
    FInfoProc := CallBack;
    FreeOnTerminate := FALSE;
    ActorID := ID;
    ActorMsg := TEvent.Create(NIL, TRUE, FALSE, '');
    MsgType := -1;
    ActorActive := TRUE;
    Processing := FALSE;

    inherited Create(Susp);
  {$IFDEF MSWINDOWS}              // Only for windows
//  Parallel.Set_Process_Priority(GetCurrentProcess(), REALTIME_PRIORITY_CLASS);
    Parallel.Set_Thread_affinity(handle, local_CPU);
//  Parallel.Set_Thread_Priority(handle,THREAD_PRIORITY_TIME_CRITICAL);
  {$ELSE}
//  Parallel.Set_Thread_Priority(self,THREAD_PRIORITY_TIME_CRITICAL);
    Parallel.Set_Thread_affinity(handle, local_CPU);
  {$ENDIF}

end;

procedure TSolver.Send_Message(Msg: Integer);
begin
    MsgType := Msg;
    ActorMsg.SetEvent;
end;

procedure TSolver.Set_Processing(NVal: Boolean);
begin
    Processing := NVal;
end;

function TSolver.Get_Processing(): Boolean;
begin
    Result := Processing;
end;

function TSolver.Get_CPU(): Integer;
begin
    Result := ActorCPU[ActorID];
end;

procedure TSolver.Set_CPU(CPU: Integer);
var
    Parallel: TParallel_Lib;
begin
    ActorCPU[ActorID] := CPU;
  {$IFDEF MSWINDOWS}              // Only for windows
    Parallel.Set_Thread_affinity(handle, CPU);
//  Parallel.Set_Thread_Priority(handle,THREAD_PRIORITY_TIME_CRITICAL);
  {$ELSE}
//  Parallel.Set_Thread_Priority(self,THREAD_PRIORITY_TIME_CRITICAL);
    Parallel.Set_Thread_affinity(handle, CPU);
  {$ENDIF}
end;

{*******************************************************************************
*             executes the selected solution algorithm                         *
********************************************************************************
}

procedure TSolver.Execute;
var
{$IFNDEF FPC}
    ScriptEd: TScriptEdit;
{$ENDIF}
    i,
    j,
    idx: Integer;
    VSourceObj: TVsourceObj;
    Volts: Polar;

begin
    with ActiveCircuit[ActorID], ActiveCircuit[ActorID].Solution do
    begin
        while ActorActive do
        begin
            ActorMsg.WaitFor(INFINITE);
            ActorMsg.ResetEvent;
            Processing := TRUE;
            case MsgType of             // Evaluates the incomming message
                SIMULATE:               // Simulates the active ciruit on this actor
                    try
                        begin                   // Checks if this is the coordinator actor in A-Diakoptics mode
                            if ((ADiakoptics and (ActorID = 1)) and not IsSolveAll) then
                                Solve_Diakoptics()
                            else
                            begin
                  // Verifies if there is an A-Diakoptics simulation running to update the local Vsources
                                if (ADiakoptics and not IsSolveAll) then
                                    Start_Diakoptics();
                  // Normal solution routine
                                case Dynavars.SolutionMode of
                                    SNAPSHOT:
                                        SolveSnap(ActorID);
                                    YEARLYMODE:
                                        SolveYearly(ActorID);
                                    DAILYMODE:
                                        SolveDaily(ActorID);
                                    DUTYCYCLE:
                                        SolveDuty(ActorID);
                                    DYNAMICMODE:
                                        SolveDynamic(ActorID);
                                    MONTECARLO1:
                                        SolveMonte1(ActorID);
                                    MONTECARLO2:
                                        SolveMonte2(ActorID);
                                    MONTECARLO3:
                                        SolveMonte3(ActorID);
                                    PEAKDAY:
                                        SolvePeakDay(ActorID);
                                    LOADDURATION1:
                                        SolveLD1(ActorID);
                                    LOADDURATION2:
                                        SolveLD2(ActorID);
                                    DIRECT:
                                        SolveDirect(ActorID);
                                    MONTEFAULT:
                                        SolveMonteFault(ActorID);  // Monte Carlo Fault Cases
                                    FAULTSTUDY:
                                        SolveFaultStudy(ActorID);
                                    AUTOADDFLAG:
                                        ActiveCircuit[ActorID].AutoAddObj.Solve(ActorID);
                                    HARMONICMODE:
                                        SolveHarmonic(ActorID);
                                    GENERALTIME:
                                        SolveGeneralTime(ActorID);
                                    HARMONICMODET:
                                        SolveHarmonicT(ActorID);  //Declares the Hsequential-time harmonics
                                else
                                    DosimpleMsg('Unknown solution mode.', 481);
                                end;
                            end;
                {$IFDEF MSWINDOWS}
                            QueryPerformanceCounter(GEndTime);
                {$ELSE}
                            GEndTime := GetTickCount64;
                {$ENDIF}
                            Total_Solve_Time_Elapsed := ((GEndTime - GStartTime) / CPU_Freq) * 1000000;
                            Total_Time_Elapsed := Total_Time_Elapsed + Total_Solve_Time_Elapsed;
                            Processing := FALSE;
                            FMessage := '1';
                            ActorStatus[ActorID] := 1;      // Global to indicate that the actor is ready

                  // If this is an A-Diakoptics actor reports the results to the coordinator (Actor 1)
                            if ADiakoptics and (ActorID <> 1) then
                                Notify_Main;

                  // Sends a message to Actor Object (UI) to notify that the actor has finised
                            UIEvent.SetEvent;
                  {$IFDEF MSWINDOWS}
                            if not ADiakoptics then
                            begin
                                if Parallel_enabled then
                                    if not IsDLL then
                                        queue(CallCallBack); // Refreshes the GUI if running asynchronously
                            end
                            else
                            begin
                                if (Parallel_enabled and (ActorID = 1)) then
                                    if not IsDLL then
                                        queue(CallCallBack); // Refreshes the GUI if running asynchronously
                            end;
                  {$ENDIF}
                        end;
                    except
                        On E: Exception do
                        begin
                            FMessage := '1';
                            ActorStatus[ActorID] := 1;      // Global to indicate that the actor is ready
                            SolutionAbort := TRUE;
                            UIEvent.SetEvent;
                            if not ADiakoptics then
                            begin
                                if Parallel_enabled then
                                    if not IsDLL then
                                        queue(CallCallBack); // Refreshes the GUI if running asynchronously
                            end
                            else
                            begin
                                if (Parallel_enabled and (ActorID = 1)) then
                                    if not IsDLL then
                                        queue(CallCallBack); // Refreshes the GUI if running asynchronously
                            end;
                            if not Parallel_enabled then
                                DoSimpleMsg('Error Encountered in Solve: ' + E.Message, 482);
                        end;
                    end;
                EXIT_ACTOR:                // Terminates the thread
                begin
                    ActorActive := FALSE;
                end
            else                       // I don't know what the message is
                DosimpleMsg('Unknown Message.', 7010);
            end;

        end;
    end;
end;

procedure TSolver.CallCallBack;
begin
    if Assigned(FInfoProc) then
        FInfoProc(FMessage);
end;

// Initializes the variables of the A-Diakoptics worker
procedure TSolver.Start_Diakoptics();
var
    row,
    j,
    i: Integer;
    VSource: TVsourceObj;
    Volts: Polar;
    CNum: Complex;
begin
    with ActiveCircuit[ActorID], ActiveCircuit[ActorID].Solution do
    begin
        j := ActiveCircuit[1].Ic.NZero - 1;    // Brings the number of Non-Zero elements from Ic
        if j > 0 then
        begin
      // Clears the local Ic vector
            for i := 1 to NumNodes do
                Ic_Local^[i] := cZERO;  // probably not necessary
      // Brings the section of the vector needed for this actor
            for i := 0 to j do
            begin
                if ActiveCircuit[1].Ic.CData[i].row >= VIndex then
                begin
                    row := ActiveCircuit[1].Ic.CData[i].row;
                    Ic_Local^[row - VIndex + 1] := ActiveCircuit[1].Ic.CData[i].Value;
                end;
            end;
      // Solves to find the total solution
            SolveSparseSet(hY, @Node_dV^[1], @Ic_Local^[1]);
      // Sends the total voltage for this part to the coordinator
            for i := 1 to NumNodes do
            begin
                CNum := csub(NodeV^[i], Node_dV^[i]);
                ActiveCircuit[1].Solution.NodeV^[i + VIndex] := CNum;
            end;

      // Sets the voltage at the feeder head
            VSource := ActiveVSource[ActorID].ElementList.First;
            for i := 1 to 3 do
            begin
                CNum := cadd(NodeV^[i], Node_dV^[i]);
                Volts := ctopolardeg(CNum);
                VSource.kVBase := Volts.mag / 1000;   // is in kV
                VSource.Angle := Volts.ang;
                VSource := ActiveVSource[ActorID].ElementList.Next;
            end;
        end;
    end;
end;

procedure TSolver.Notify_Main;
var
    CNum: Complex;
    i, j,
    idx: Integer;
begin
  // Will do something
    with ActiveCircuit[ActorID], ActiveCircuit[ActorID].Solution do
    begin
        i := NumNodes;
        for idx := 1 to i do
        begin
      // if it doesn't includes any power injection element (Isource, VSource)
      // returns dV to correct the interconnection equation
            if ActorID > 2 then
                CNum := csub(NodeV^[idx], Node_dV^[idx])
            else
                CNum := NodeV^[idx];
            ActiveCircuit[1].V_0.Insert((idx + VIndex - 1), 0, CNum);
        end;
    end;

end;

procedure TSolver.DoTerminate;        // Is the end of the thread
var
    ex: TObject;
begin
    ActorActive := FALSE;
    Processing := FALSE;
    ActorStatus[ActorID] := 1;      // Global to indicate that the actor is ready
    UIEvent.SetEvent;
    ActorMsg.Free;
//    Freeandnil(UIEvent);
    inherited;
end;

destructor TSolver.Destroy;
begin
    inherited destroy;
end;

initialization

    IsMultiThread := TRUE;
    {$IFDEF debugtrace}
    Assignfile(Fdebug, 'Debugtrace.csv');
    Rewrite(Fdebug);
    CloseFile(Fdebug);
   {$ENDIF}

end.
