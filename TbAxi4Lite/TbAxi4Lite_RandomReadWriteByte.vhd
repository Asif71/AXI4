--
--  File Name:         TbAxi4Lite_RandomReadWriteByte.vhd
--  Design Unit Name:  Architecture of TestCtrl
--  Revision:          OSVVM MODELS STANDARD VERSION
--
--  Maintainer:        Jim Lewis      email:  jim@synthworks.com
--  Contributor(s):
--     Jim Lewis      jim@synthworks.com
--
--
--  Description:
--      Test transaction source
--
--
--  Developed by:
--        SynthWorks Design Inc.
--        VHDL Training Classes
--        http://www.SynthWorks.com
--
--  Revision History:
--    Date       Version    Description
--    09/2017:   2017       Initial revision
--
--
-- Copyright 2017 SynthWorks Design Inc
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
--
architecture RandomReadWriteByte of TestCtrl is

  signal TestDone : integer_barrier := 1 ;
  constant AXI_ADDR_WIDTH : integer := 32 ; 
  constant AXI_DATA_WIDTH : integer := 32 ; 
  constant AXI_DATA_BYTES : integer := AXI_DATA_WIDTH / 8 ; 
  
  type OpType is (WRITE_OP_ENUM, READ_OP_ENUM) ;  -- Add TEST_DONE?
  -- constant NO_OP_INDEX    : integer := OpType'pos(NO_OP) ;
  constant WRITE_OP_INDEX : integer := OpType'pos(WRITE_OP_ENUM) ;
  constant READ_OP_INDEX  : integer := OpType'pos(READ_OP_ENUM) ;
  subtype OperationType is std_logic_vector(0 downto 0) ;
  constant WRITE_OP : OperationType := to_slv(WRITE_OP_INDEX, OperationType'length) ;
  constant READ_OP : OperationType := to_slv(READ_OP_INDEX, OperationType'length) ;

  shared variable OperationFifo  : osvvm.ScoreboardPkg_slv.ScoreboardPType ; 
  
  signal TestActive : boolean := TRUE ;
  
  signal OperationCount : integer := 0 ; 
 
begin

  ------------------------------------------------------------
  -- ControlProc
  --   Set up AlertLog and wait for end of test
  ------------------------------------------------------------
  ControlProc : process
  begin
    -- Initialization of test
    SetAlertLogName("TbAxi4Lite_RandomReadWriteByte") ;
    SetLogEnable(PASSED, TRUE) ;    -- Enable PASSED logs
    SetLogEnable(INFO, TRUE) ;    -- Enable INFO logs

    -- Wait for testbench initialization 
    wait for 0 ns ;  wait for 0 ns ;
    TranscriptOpen("./results/TbAxi4Lite_RandomReadWriteByte.txt") ;
    SetTranscriptMirror(TRUE) ; 

    -- Wait for Design Reset
    wait until nReset = '1' ;  
    ClearAlerts ;
    SetAlertStopCount(ERROR, 2) ;

    -- Wait for test to finish
    WaitForBarrier(TestDone, 1 ms) ;
    AlertIf(now >= 1 ms, "Test finished due to timeout") ;
    AlertIf(GetAffirmCount < 1, "Test is not Self-Checking");
    
--    TranscriptClose ; 
--    AlertIfDiff("./results/TbAxi4Lite_RandomReadWriteByte.txt", "../sim_shared/validated_results/TbAxi4Lite_RandomReadWriteByte.txt", "") ; 
    
    print("") ;
    ReportAlerts ; 
    print("") ;
    std.env.stop ; 
    wait ; 
  end process ControlProc ; 

  
  ------------------------------------------------------------
  -- AxiMasterProc
  --   Generate transactions for AxiMaster
  ------------------------------------------------------------
  AxiMasterProc : process
    variable OpRV           : RandomPType ;   
    variable NoOpRV         : RandomPType ;   
    variable DataRV         : RandomPType ;   
    variable Operation      : OperationType ; 
    variable Address        : std_logic_vector(AXI_ADDR_WIDTH-1 downto 0) ;
    variable ByteAddress    : integer ;
    variable NumberOfBytes  : integer ;
    variable MasterData     : std_logic_vector(AXI_DATA_WIDTH-1 downto 0) ;    
    variable SlaveData      : std_logic_vector(AXI_DATA_WIDTH-1 downto 0) ;    
    variable ReadData       : std_logic_vector(AXI_DATA_WIDTH-1 downto 0) ;    
    
    variable counts : integer_vector(0 to OpType'Pos(OpType'Right)) ; 
  begin
    -- Initialize Randomization Objects
    OpRV.InitSeed(OpRv'instance_name) ;
    NoOpRV.InitSeed(NoOpRV'instance_name) ;
    DataRV.InitSeed(DataRV'instance_name) ;
    
    -- Find exit of reset
    wait until nReset = '1' ;  
    NoOp(AxiMasterTransRec, 2) ; 
    
    -- Distribution for Test Operations
    counts := (WRITE_OP_INDEX => 500, READ_OP_INDEX => 500) ;
    
    OperationLoop : loop
      -- Calculate Address and Data if Write or Read Operation
      Operation      := to_slv(OpRV.DistInt(counts), Operation'length) ;
      Address        := OpRV.RandSlv(size => AXI_ADDR_WIDTH) ;
      ByteAddress    := to_integer(Address(1 downto 0)) ;
      NumberOfBytes  := OpRv.RandInt(1, AXI_DATA_BYTES - ByteAddress) ;

      -- Get MasterData right aligned and SlaveData word aligned
      SlaveData      := (others => '0') ;
      MasterData     := (others => '0') ;
      for i in AXI_DATA_BYTES - 1 downto 0 loop
        SlaveData := SlaveData(AXI_DATA_BYTES*8 - 9 downto 0) & (0 to 7 => '0') ;
        if i >= ByteAddress and i < ByteAddress + NumberOfBytes then
          SlaveData(7 downto 0) := DataRV.RandSlv(0, 255, 8) ;
          MasterData := MasterData(AXI_DATA_BYTES*8 - 9 downto 0) & SlaveData(7 downto 0) ;
        end if ; 
      end loop ;
      
      -- Send the operation to the Slave Handler
      OperationFifo.push(Operation & Address & SlaveData) ;
      Increment(OperationCount) ;
      
      -- 20 % of the time add a no-op cycle with a delay of 1 to 5 clocks
      if NoOpRV.DistInt((8, 2)) = 1 then 
        NoOp(AxiMasterTransRec, NoOpRV.RandInt(1, 5)) ; 
      end if ; 
      
      -- Do the Operation
      case Operation is
        when WRITE_OP =>  
          counts(WRITE_OP_INDEX) := counts(WRITE_OP_INDEX) - 1 ; 
          -- Log("Starting: Master Write with Address: " & to_hstring(Address) & "  Data: " & to_hstring(Data) ) ;
          MasterWrite(AxiMasterTransRec, Address, MasterData(NumberOfBytes*8-1 downto 0)) ;
          
        when READ_OP =>  
          counts(READ_OP_INDEX) := counts(READ_OP_INDEX) - 1 ; 
          -- Log("Starting: Master Read with Address: " & to_hstring(Address) & "  Data: " & to_hstring(Data) ) ;
          ReadData := (others => '0') ;  -- Clear out all data values for short reads
          MasterRead(AxiMasterTransRec, Address, ReadData(NumberOfBytes*8-1 downto 0)) ;
          AffirmIf(ReadData = MasterData, "AXI Master Read Data: "& to_hstring(ReadData), 
                   "  Expected: " & to_hstring(MasterData) & "  ByteAddress: " & to_string(ByteAddress)) ;

        when others =>
          Alert("Invalid Operation Generated", FAILURE) ;
      end case ;
      
      exit when counts = (0, 0) ;
    end loop OperationLoop ; 
    
    TestActive <= FALSE ; 
    -- Allow slave to catch up before signaling OperationCount (needed when WRITE_OP is last)
    -- wait for 0 ns ;  -- this is enough
    NoOp(AxiMasterTransRec, 2) ;
    Increment(OperationCount) ;
    
    -- Wait for outputs to propagate and signal TestDone
    NoOp(AxiMasterTransRec, 2) ;
    WaitForBarrier(TestDone) ;
    wait ;
  end process AxiMasterProc ;


  ------------------------------------------------------------
  -- AxiSlaveProc
  --   Generate transactions for AxiSlave
  ------------------------------------------------------------
  AxiSlaveProc : process
    variable NoOpRV         : RandomPType ;   
    variable Operation      : OperationType ; 
    variable Address        : std_logic_vector(AXI_ADDR_WIDTH-1 downto 0) ;
    variable ActualAddress  : std_logic_vector(AXI_ADDR_WIDTH-1 downto 0) ;
    variable Data           : std_logic_vector(AXI_DATA_WIDTH-1 downto 0) ;    
    variable WriteData      : std_logic_vector(AXI_DATA_WIDTH-1 downto 0) ;    
  begin
    NoOpRV.InitSeed(NoOpRV'instance_name) ;

    OperationLoop : loop   
      if OperationFifo.empty then
        WaitForToggle(OperationCount) ; 
      end if ; 
      
      exit OperationLoop when TestActive = FALSE ; 
      
      -- 20 % of the time add a no-op cycle with a delay of 1 to 5 clocks
      if NoOpRV.DistInt((8, 2)) = 1 then 
        NoOp(AxiSlaveTransRec, NoOpRV.RandInt(1, 5)) ; 
      end if ; 
      
      -- Get the Operation
      (Operation, Address, Data) := OperationFifo.pop ; 
      
      -- Do the Operation
      case Operation is
        when WRITE_OP =>  
          -- Log("Starting: Slave Write with Expected Address: " & to_hstring(Address) & "  Data: " & to_hstring(Data) ) ;
          SlaveGetWrite(AxiSlaveTransRec, ActualAddress, WriteData) ;
          AffirmIf(ActualAddress = Address, "AXI Slave Write Address: " & to_hstring(ActualAddress), 
                   "  Expected: " & to_hstring(Address)) ;
          AffirmIf(WriteData = Data, "AXI Slave Write Data: "& to_hstring(WriteData), 
                   "  Expected: " & to_hstring(Data)) ;
          
        when READ_OP =>  
          -- Log("Starting: Slave Read with Expected Address: " & to_hstring(Address) & "  Data: " & to_hstring(Data) ) ;
          SlaveRead(AxiSlaveTransRec, ActualAddress, Data) ; 
          AffirmIf(ActualAddress = Address, "AXI Slave Read Address: " & to_hstring(ActualAddress), 
                   "  Expected: " & to_hstring(Address)) ;

        when others =>
          Alert("Invalid Operation Generated", FAILURE) ;
          
      end case ;
      
    end loop OperationLoop ; 

    -- Wait for outputs to propagate and signal TestDone
    -- NoOp(AxiSlaveTransRec, 2) ;
    WaitForBarrier(TestDone) ;
    wait ;
  end process AxiSlaveProc ;


end RandomReadWriteByte ;

Configuration TbAxi4Lite_RandomReadWriteByte of TbAxi4Lite is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(RandomReadWriteByte) ; 
    end for ; 
  end for ; 
end TbAxi4Lite_RandomReadWriteByte ; 