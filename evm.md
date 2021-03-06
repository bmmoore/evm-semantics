EVM Execution
=============

The EVM is a stack machine over some simple opcodes.
Most of the opcodes are "local" to the execution state of the machine, but some of them must interact with the world state.
This file only defines the local execution operations, the file `ethereum.md` will define the interactions with the world state.

```{.k .uiuck .rvk}
requires "data.k"

module EVM
    imports STRING
    imports EVM-DATA
```

Configuration
-------------

The configuration has cells for the current account id, the current opcode, the program counter, the current gas, the gas price, the current program, the word stack, and the local memory.
In addition, there are cells for the callstack and execution substate.

We've broken up the configuration into two components; those parts of the state that mutate during execution of a single transaction and those that are static throughout.
In the comments next to each cell, we've marked which component of the yellowpaper state corresponds to each cell.

```{.k .uiuck .rvk}
    configuration <k> $PGM:EthereumSimulation </k>
                  <exit-code exit=""> 1 </exit-code>
                  <mode> $MODE:Mode </mode>
                  <schedule> $SCHEDULE:Schedule </schedule>
                  <analysis> .Map </analysis>

                  <ethereum>

                    // EVM Specific
                    // ============

                    <evm>

                      // Mutable during a single transaction
                      // -----------------------------------

                      <output>        .WordStack </output>              // H_RETURN
                      <memoryUsed>    0          </memoryUsed>          // \mu_i
                      <callDepth>     0          </callDepth>
                      <callStack>     .List      </callStack>
                      <interimStates> .List      </interimStates>
                      <callLog>       .Set       </callLog>

                      <txExecState>
                        <program> .Map </program>                       // I_b

                        // I_*
                        <id>        0          </id>                    // I_a
                        <caller>    0          </caller>                // I_s
                        <callData>  .WordStack </callData>              // I_d
                        <callValue> 0          </callValue>             // I_v

                        // \mu_*
                        <wordStack>   .WordStack </wordStack>           // \mu_s
                        <localMem>    .Map       </localMem>            // \mu_m
                        <pc>          0          </pc>                  // \mu_pc
                        <gas>         0          </gas>                 // \mu_g
                        <previousGas> 0          </previousGas>
                      </txExecState>

                      // A_* (execution substate)
                      <substate>
                        <selfDestruct> .Set </selfDestruct>             // A_s
                        <log>          .Set </log>                      // A_l
                        <refund>       0    </refund>                   // A_r
                      </substate>

                      // Immutable during a single transaction
                      // -------------------------------------

                      <gasPrice> 0 </gasPrice>                          // I_p
                      <origin>   0 </origin>                            // I_o

                      // I_H* (block information)
                      <previousHash>     0          </previousHash>     // I_Hp
                      <ommersHash>       0          </ommersHash>       // I_Ho
                      <coinbase>         0          </coinbase>         // I_Hc
                      <stateRoot>        0          </stateRoot>        // I_Hr
                      <transactionsRoot> 0          </transactionsRoot> // I_Ht
                      <receiptsRoot>     0          </receiptsRoot>     // I_He
                      <logsBloom>        .WordStack </logsBloom>        // I_Hb
                      <difficulty>       0          </difficulty>       // I_Hd
                      <number>           0          </number>           // I_Hi
                      <gasLimit>         0          </gasLimit>         // I_Hl
                      <gasUsed>          0          </gasUsed>          // I_Hg
                      <timestamp>        0          </timestamp>        // I_Hs
                      <extraData>        .WordStack </extraData>        // I_Hx
                      <mixHash>          0          </mixHash>          // I_Hm
                      <nonce>            0          </nonce>            // I_Hn

                      <ommerBlockHeaders> [ .JSONList ] </ommerBlockHeaders>

                    </evm>

                    // Ethereum Network
                    // ================

                    <network>

                      // Accounts Record
                      // ---------------

                      <activeAccounts> .Set </activeAccounts>
                      <accounts>
```

-   UIUC-K and RV-K have slight differences of opinion here.

```{.k .uiuck}
                        <account multiplicity="*" type="Bag">
```

```{.k .rvk}
                        <account multiplicity="*" type="Map">
```

```{.k .uiuck .rvk}
                          <acctID>  0    </acctID>
                          <balance> 0    </balance>
                          <code>    .Map </code>
                          <storage> .Map </storage>
                          <acctMap> .Map </acctMap>
                        </account>
                      </accounts>

                      // Transactions Record
                      // -------------------

                      <txOrder>   .List </txOrder>
                      <txPending> .List </txPending>

                      <messages>
```

-   UIUC-K and RV-K have slight differences of opinion here.

```{.k .uiuck}
                        <message multiplicity="*" type="Bag">
```

```{.k .rvk}
                        <message multiplicity="*" type="Map">
```

```{.k .uiuck .rvk}
                          <msgID>      0          </msgID>
                          <txNonce>    0          </txNonce>            // T_n
                          <txGasPrice> 0          </txGasPrice>         // T_p
                          <txGasLimit> 0          </txGasLimit>         // T_g
                          <to>         0          </to>                 // T_t
                          <value>      0          </value>              // T_v
                          <v>          0          </v>                  // T_w
                          <r>          .WordStack </r>                  // T_r
                          <s>          .WordStack </s>                  // T_s
                          <data>       .WordStack </data>               // T_i/T_e
                        </message>
                      </messages>

                    </network>

                  </ethereum>

    syntax EthereumSimulation
 // -------------------------
```

Modal Semantics
---------------

Our semantics is modal, with the initial mode being set on the command line via `-cMODE=EXECMODE`.

-   `NORMAL` executes as a client on the network would.
-   `VMTESTS` skips `CALL*` and `CREATE` operations.

```{.k .uiuck .rvk}
    syntax Mode ::= "NORMAL" | "VMTESTS"
```

-   `#setMode_` sets the mode to the supplied one.

```{.k .uiuck .rvk}
    syntax Mode ::= "#setMode" Mode
 // -------------------------------
    rule <k> #setMode EXECMODE => . ... </k> <mode> _ => EXECMODE </mode>
    rule <k> EX:Exception ~> (#setMode _ => .) ... </k>
```

Hardware
--------

The `callStack` cell stores a list of previous VM execution states.

-   `#pushCallStack` saves a copy of VM execution state on the `callStack`.
-   `#popCallStack` restores the top element of the `callStack`.
-   `#dropCallStack` removes the top element of the `callStack`.

```{.k .uiuck .rvk}
    syntax State ::= "{" Int "|" Int "|" Map "|" Int "|" WordStack "|" Int "|" WordStack "|" Map "|" Int "|" Int "}"
 // ----------------------------------------------------------------------------------------------------------------

    syntax InternalOp ::= "#pushCallStack"
 // --------------------------------------
    rule <k> #pushCallStack => . ... </k>
         <callStack>  (.List => ListItem({ ACCT | GAVAIL | PGM | CR | CD | CV | WS | LM | MUSED | PCOUNT })) ... </callStack>
         <id>         ACCT   </id>
         <gas>        GAVAIL </gas>
         <program>    PGM    </program>
         <caller>     CR     </caller>
         <callData>   CD     </callData>
         <callValue>  CV     </callValue>
         <wordStack>  WS     </wordStack>
         <localMem>   LM     </localMem>
         <memoryUsed> MUSED  </memoryUsed>
         <pc>         PCOUNT </pc>

    syntax InternalOp ::= "#popCallStack"
 // -------------------------------------
    rule <k> #popCallStack => . ... </k>
         <callStack>  (ListItem({ ACCT | GAVAIL | PGM | CR | CD | CV | WS | LM | MUSED | PCOUNT }) => .List) ... </callStack>
         <id>         _ => ACCT   </id>
         <gas>        _ => GAVAIL </gas>
         <program>    _ => PGM    </program>
         <caller>     _ => CR     </caller>
         <callData>   _ => CD     </callData>
         <callValue>  _ => CV     </callValue>
         <wordStack>  _ => WS     </wordStack>
         <localMem>   _ => LM     </localMem>
         <memoryUsed> _ => MUSED  </memoryUsed>
         <pc>         _ => PCOUNT </pc>

    syntax InternalOp ::= "#dropCallStack"
 // --------------------------------------
    rule <k> #dropCallStack => . ... </k> <callStack> (ListItem(_) => .List) ... </callStack>
```

The `interimStates` cell stores a list of previous world states.

-   `#pushWorldState` stores a copy of the current accounts at the top of the `interimStates` cell.
-   `#popWorldState` restores the top element of the `interimStates`.
-   `#dropWorldState` removes the top element of the `interimStates`.

```{.k .uiuck .rvk}
    syntax Account ::= "{" Int "|" Int "|" Map "|" Map "|" Map "}"
 // --------------------------------------------------------------

    syntax InternalOp ::= "#pushWorldState" | "#pushWorldStateAux" Set | "#pushAccount" Int
 // ---------------------------------------------------------------------------------------
    rule <k> #pushWorldState => #pushWorldStateAux ACCTS ... </k>
         <activeAccounts> ACCTS </activeAccounts>
         <interimStates> (.List => ListItem(.Set)) ... </interimStates>

    rule <k> #pushWorldStateAux .Set => . ... </k>
    rule <k> #pushWorldStateAux (SetItem(ACCT) REST) => #pushAccount ACCT ~> #pushWorldStateAux REST ... </k>
    rule <k> #pushAccount ACCT => . ... </k>
         <interimStates> ListItem((.Set => SetItem({ ACCT | BAL | CODE | STORAGE | ACCTMAP })) REST) ... </interimStates>
         <account>
           <acctID> ACCT </acctID>
           <balance> BAL </balance>
           <code> CODE </code>
           <storage> STORAGE </storage>
           <acctMap> ACCTMAP </acctMap>
         </account>

    syntax InternalOp ::= "#popWorldState" | "#popWorldStateAux" Set
 // ----------------------------------------------------------------
    rule <k> #popWorldState => #popWorldStateAux PREVSTATE ... </k>
         <interimStates> (ListItem(PREVSTATE) => .List) ... </interimStates>
         <activeAccounts> _ => .Set </activeAccounts>
         <accounts> _ => .Bag </accounts>

    rule <k> #popWorldStateAux .Set => . ... </k>
    rule <k> #popWorldStateAux ( (SetItem({ ACCT | BAL | CODE | STORAGE | ACCTMAP }) => .Set) REST ) ... </k>
         <activeAccounts> ... (.Set => SetItem(ACCT)) </activeAccounts>
         <accounts> ( .Bag
                   => <account>
                        <acctID> ACCT </acctID>
                        <balance> BAL </balance>
                        <code> CODE </code>
                        <storage> STORAGE </storage>
                        <acctMap> ACCTMAP </acctMap>
                      </account>
                    )
                    ...
         </accounts>

    syntax InternalOp ::= "#dropWorldState"
 // ---------------------------------------
    rule <k> #dropWorldState => . ... </k> <interimStates> (ListItem(_) => .List) ... </interimStates>
```

Simple commands controlling exceptions provide control-flow.

-   `#end` is used to indicate the (non-exceptional) end of execution.
-   `#exception` is used to indicate exceptional states (it consumes any operations to be performed after it).
-   `#?_:_?#` allows for branching control-flow; if it reaches the front of the `op` cell it takes the first branch, if an exception runs into it it takes the second branch.

```{.k .uiuck .rvk}
    syntax KItem ::= Exception
    syntax Exception ::= "#exception" | "#end"
 // ------------------------------------------
    rule <k> EX:Exception ~> (_:Int    => .) ... </k>
    rule <k> EX:Exception ~> (_:OpCode => .) ... </k>

    syntax KItem ::= "#?" K ":" K "?#"
 // ----------------------------------
    rule <k>                #? K : _ ?#  => K         ... </k>
    rule <k> #exception ~>  #? _ : K ?#  => K         ... </k>
    rule <k> #end       ~> (#? K : _ ?#) => K ~> #end ... </k>
```

OpCode Execution Cycle
----------------------

`OpCode` is broken into several subsorts for easier handling.
Here all `OpCode`s are subsorted into `KItem` (allowing sequentialization), and the various sorts of opcodes are subsorted into `OpCode`.

```{.k .uiuck .rvk}
    syntax KItem  ::= OpCode
    syntax OpCode ::= NullStackOp | UnStackOp | BinStackOp | TernStackOp | QuadStackOp
                    | InvalidOp | StackOp | InternalOp | CallOp | CallSixOp | PushOp
 // --------------------------------------------------------------------------------
```

-   `#execute` calls `#next` repeatedly until it recieves an `#end` or `#exception`.
-   `#execTo` executes until the next opcode is one of the specified ones.

```{.k .uiuck .rvk}
    syntax KItem ::= "#execute"
 // ---------------------------
    rule <k> (. => #next) ~> #execute ... </k>
    rule <k> EX:Exception ~> (#execute => .)  ... </k>

    syntax InternalOp ::= "#execTo" Set
 // -----------------------------------
    rule <k> (. => #next) ~> #execTo OPS ... </k>
         <pc> PCOUNT </pc>
         <program> ... PCOUNT |-> OP ... </program>
      requires notBool (OP in OPS)

    rule <k> #execTo OPS => . ... </k>
         <pc> PCOUNT </pc>
         <program> ... PCOUNT |-> OP ... </program>
      requires OP in OPS

    rule <k> #execTo OPS => #end ... </k>
         <pc> PCOUNT </pc>
         <program> PGM </program>
      requires notBool PCOUNT in keys(PGM)
```

Execution follows a simple cycle where first the state is checked for exceptions, then if no exceptions will be thrown the opcode is run.

-   Regardless of the mode, `#next` will throw `#end` or `#exception` if the current program counter is not pointing at an OpCode.

TODO: I think on `#next` we are supposed to pretend it's `STOP` if it's in the middle of the program somewhere but is invalid?
I suppose the semantics currently loads `INVALID(N)` where `N` is the position in the bytecode array.

```{.k .uiuck .rvk}
    syntax InternalOp ::= "#next"
 // -----------------------------
    rule <k> #next => #if PCOUNT <Int #sizeOpCodeMap(PGM) #then #exception #else #end #fi ... </k>
         <pc> PCOUNT </pc>
         <program> PGM </program>
      requires notBool (PCOUNT in_keys(PGM))
```

-   In `NORMAL` or `VMTESTS` mode, `#next` checks if the opcode is exceptional, runs it if not, then increments the program counter.

```{.k .uiuck .rvk}
    rule <mode> EXECMODE </mode>
         <k> #next
          => #pushCallStack
          ~> #exceptional? [ OP ] ~> #exec [ OP ] ~> #pc [ OP ]
          ~> #? #dropCallStack : #popCallStack ~> #exception ?#
         ...
         </k>
         <pc> PCOUNT </pc>
         <program> ... PCOUNT |-> OP ... </program>
      requires EXECMODE in (SetItem(NORMAL) SetItem(VMTESTS))
```

### Exceptional OpCodes

Some checks if an opcode will throw an exception are relatively quick and done up front.

-   `#exceptional?` checks if the operator is invalid and will not cause `wordStack` size issues (this implements the function `Z` in the yellowpaper, section 9.4.2).

```{.k .uiuck .rvk}
    syntax InternalOp ::= "#exceptional?" "[" OpCode "]"
 // ----------------------------------------------------
    rule <k> #exceptional? [ OP ] => #invalid? [ OP ] ~> #stackNeeded? [ OP ] ~> #badJumpDest? [ OP ] ... </k>
```

-   `#invalid?` checks if it's the designated invalid opcode.

```{.k .uiuck .rvk}
    syntax InternalOp ::= "#invalid?" "[" OpCode "]"
 // ------------------------------------------------
    rule <k> #invalid? [ INVALID(_) ] => #exception ... </k>
    rule <k> #invalid? [ OP         ] => .          ... </k> requires notBool isInvalidOp(OP)
```

-   `#stackNeeded?` checks that the stack will be not be under/overflown.
-   `#stackNeeded`, `#stackAdded`, and `#stackDelta` are helpers for deciding `#stackNeeded?`.

```{.k .uiuck .rvk}
    syntax InternalOp ::= "#stackNeeded?" "[" OpCode "]"
 // ----------------------------------------------------
    rule <k> #stackNeeded? [ OP ] => #exception ... </k>
         <wordStack> WS </wordStack>
   requires #sizeWordStack(WS) <Int #stackNeeded(OP)
     orBool #sizeWordStack(WS) +Int #stackDelta(OP) >Int 1024

    rule <k> #stackNeeded? [ OP ] => .K ... </k>
         <wordStack> WS </wordStack>
    requires notBool (#sizeWordStack(WS) <Int #stackNeeded(OP)
             orBool   #sizeWordStack(WS) +Int #stackDelta(OP) >Int 1024)

    syntax Int ::= #stackNeeded ( OpCode ) [function]
 // -------------------------------------------------
    rule #stackNeeded(PUSH(_, _))      => 0
    rule #stackNeeded(NOP:NullStackOp) => 0
    rule #stackNeeded(UOP:UnStackOp)   => 1
    rule #stackNeeded(BOP:BinStackOp)  => 2 requires notBool isLogOp(BOP)
    rule #stackNeeded(TOP:TernStackOp) => 3
    rule #stackNeeded(QOP:QuadStackOp) => 4
    rule #stackNeeded(DUP(N))          => N
    rule #stackNeeded(SWAP(N))         => N +Int 1
    rule #stackNeeded(LOG(N))          => N +Int 2
    rule #stackNeeded(DELEGATECALL)    => 6
    rule #stackNeeded(COP:CallOp)      => 7 requires COP =/=K DELEGATECALL

    syntax Int ::= #stackAdded ( OpCode ) [function]
 // ------------------------------------------------
    rule #stackAdded(CALLDATACOPY) => 0
    rule #stackAdded(CODECOPY)     => 0
    rule #stackAdded(EXTCODECOPY)  => 0
    rule #stackAdded(POP)          => 0
    rule #stackAdded(MSTORE)       => 0
    rule #stackAdded(MSTORE8)      => 0
    rule #stackAdded(SSTORE)       => 0
    rule #stackAdded(JUMP)         => 0
    rule #stackAdded(JUMPI)        => 0
    rule #stackAdded(JUMPDEST)     => 0
    rule #stackAdded(STOP)         => 0
    rule #stackAdded(RETURN)       => 0
    rule #stackAdded(SELFDESTRUCT) => 0
    rule #stackAdded(PUSH(_,_))    => 1
    rule #stackAdded(LOG(_))       => 0
    rule #stackAdded(SWAP(N))      => N
    rule #stackAdded(DUP(N))       => N +Int 1
    rule #stackAdded(OP)           => 1 [owise]

    syntax Int ::= #stackDelta ( OpCode ) [function]
 // ------------------------------------------------
    rule #stackDelta(OP) => #stackAdded(OP) -Int #stackNeeded(OP)
```

-   `#badJumpDest?` determines if the opcode will result in a bad jump destination.

```{.k .uiuck .rvk}
    syntax InternalOp ::= "#badJumpDest?" "[" OpCode "]"
 // ----------------------------------------------------
    rule <k> #badJumpDest? [ OP    ] => . ... </k> requires notBool isJumpOp(OP)
    rule <k> #badJumpDest? [ OP    ] => . ... </k> <wordStack> DEST  : WS </wordStack> <program> ... DEST |-> JUMPDEST ... </program> requires isJumpOp(OP)
    rule <k> #badJumpDest? [ JUMPI ] => . ... </k> <wordStack> _ : 0 : WS </wordStack>

    rule <k> #badJumpDest? [ JUMP  ] => #exception ... </k> <wordStack> DEST :     WS </wordStack> <program> ... DEST |-> OP ... </program> requires OP =/=K JUMPDEST
    rule <k> #badJumpDest? [ JUMPI ] => #exception ... </k> <wordStack> DEST : W : WS </wordStack> <program> ... DEST |-> OP ... </program> requires OP =/=K JUMPDEST andBool W =/=K 0

    rule <k> #badJumpDest? [ JUMP  ] => #exception ... </k> <wordStack> DEST :     WS </wordStack> <program> PGM </program> requires notBool (DEST in_keys(PGM))
    rule <k> #badJumpDest? [ JUMPI ] => #exception ... </k> <wordStack> DEST : W : WS </wordStack> <program> PGM </program> requires (notBool (DEST in_keys(PGM))) andBool W =/=K 0
```

### Execution Step

-   `#exec` will load the arguments of the opcode (it assumes `#stackNeeded?` is accurate and has been called) and trigger the subsequent operations.

```{.k .uiuck .rvk}
    syntax InternalOp ::= "#exec" "[" OpCode "]"
 // --------------------------------------------
    rule <k> #exec [ OP ] => #gas [ OP ] ~> OP ... </k> requires isInternalOp(OP) orBool isNullStackOp(OP) orBool isPushOp(OP)
```

Here we load the correct number of arguments from the `wordStack` based on the sort of the opcode.
Some of them require an argument to be interpereted as an address (modulo 160 bits), so the `#addr?` function performs that check.

```{.k .uiuck .rvk}
    syntax InternalOp ::= UnStackOp Int
                        | BinStackOp Int Int
                        | TernStackOp Int Int Int
                        | QuadStackOp Int Int Int Int
 // -------------------------------------------------
    rule <k> #exec [ UOP:UnStackOp   => UOP #addr?(UOP, W0)          ] ... </k> <wordStack> W0 : WS                => WS </wordStack>
    rule <k> #exec [ BOP:BinStackOp  => BOP #addr?(BOP, W0) W1       ] ... </k> <wordStack> W0 : W1 : WS           => WS </wordStack>
    rule <k> #exec [ TOP:TernStackOp => TOP #addr?(TOP, W0) W1 W2    ] ... </k> <wordStack> W0 : W1 : W2 : WS      => WS </wordStack>
    rule <k> #exec [ QOP:QuadStackOp => QOP #addr?(QOP, W0) W1 W2 W3 ] ... </k> <wordStack> W0 : W1 : W2 : W3 : WS => WS </wordStack>

    syntax Int ::= "#addr?" "(" OpCode "," Int ")" [function]
 // ---------------------------------------------------------
    rule #addr?(BALANCE,      W) => #addr(W)
    rule #addr?(EXTCODESIZE,  W) => #addr(W)
    rule #addr?(EXTCODECOPY,  W) => #addr(W)
    rule #addr?(SELFDESTRUCT, W) => #addr(W)
    rule #addr?(OP, W)           => W        requires (OP =/=K BALANCE) andBool (OP =/=K EXTCODESIZE) andBool (OP =/=K EXTCODECOPY) andBool (OP =/=K SELFDESTRUCT)
```

`StackOp` is used for opcodes which require a large portion of the stack.

```{.k .uiuck .rvk}
    syntax InternalOp ::= StackOp WordStack
 // ---------------------------------------
    rule <k> #exec [ SO:StackOp => SO WS ] ... </k> <wordStack> WS </wordStack>
```

The `CallOp` opcodes all interperet their second argument as an address.

```{.k .uiuck .rvk}
    syntax InternalOp ::= CallSixOp Int Int     Int Int Int Int
                        | CallOp    Int Int Int Int Int Int Int
 // -----------------------------------------------------------
    rule <k> #exec [ CSO:CallSixOp => CSO W0 #addr(W1)    W2 W3 W4 W5 ] ... </k> <wordStack> W0 : W1 : W2 : W3 : W4 : W5 : WS      => WS </wordStack>
    rule <k> #exec [ CO:CallOp     => CO  W0 #addr(W1) W2 W3 W4 W5 W6 ] ... </k> <wordStack> W0 : W1 : W2 : W3 : W4 : W5 : W6 : WS => WS </wordStack>
```

-   `#gas` calculates how much gas this operation costs, and takes into account the memory consumed.

```{.k .uiuck .rvk}
    syntax InternalOp ::= "#gas" "[" OpCode "]" | "#deductGas"
 // ----------------------------------------------------------
    rule <k> #gas [ OP ] => #gasExec(SCHED, OP) ~> #memory(OP, MU) ~> #deductGas ... </k> <memoryUsed> MU </memoryUsed> <schedule> SCHED </schedule>

    rule <k> GEXEC:Int ~> MU':Int ~> #deductGas => #exception ... </k> requires MU' >=Int pow256
    rule <k> (GEXEC:Int ~> MU':Int => (Cmem(SCHED, MU') -Int Cmem(SCHED, MU)) +Int GEXEC)  ~> #deductGas ... </k>
         <memoryUsed> MU => MU' </memoryUsed> <schedule> SCHED </schedule>
      requires MU' <Int pow256

    rule <k> G:Int ~> #deductGas => #exception ... </k> <gas> GAVAIL                  </gas> requires GAVAIL <Int G
    rule <k> G:Int ~> #deductGas => .          ... </k> <gas> GAVAIL => GAVAIL -Int G </gas> <previousGas> _ => GAVAIL </previousGas> requires GAVAIL >=Int G

    syntax Int ::= Cmem ( Schedule , Int ) [function, memo]
 // -------------------------------------------------------
    rule Cmem(SCHED, N) => (N *Int Gmemory < SCHED >) +Int ((N *Int N) /Int Gquadcoeff < SCHED >)
```

### Program Counter

All operators except for `PUSH` and `JUMP*` increment the program counter by 1.
The arguments to `PUSH` must be skipped over (as they are inline), and the opcode `JUMP` already affects the program counter in the correct way.

-   `#pc` calculates the next program counter of the given operator.

```{.k .uiuck .rvk}
    syntax InternalOp ::= "#pc" "[" OpCode "]"
 // ------------------------------------------
    rule <k> #pc [ OP         ] => . ... </k> <pc> PCOUNT => PCOUNT +Int 1          </pc> requires notBool (isPushOp(OP) orBool isJumpOp(OP))
    rule <k> #pc [ PUSH(N, _) ] => . ... </k> <pc> PCOUNT => PCOUNT +Int (1 +Int N) </pc>
    rule <k> #pc [ OP         ] => . ... </k> requires isJumpOp(OP)

    syntax Bool ::= isJumpOp ( OpCode ) [function]
 // ----------------------------------------------
    rule isJumpOp(OP) => OP ==K JUMP orBool OP ==K JUMPI
```

### Substate Log

During execution of a transaction some things are recorded in the substate log (Section 6.1 in yellowpaper).
This is a right cons-list of `SubstateLogEntry` (which contains the account ID along with the specified portions of the `wordStack` and `localMem`).

```{.k .uiuck .rvk}
    syntax SubstateLogEntry ::= "{" Int "|" WordStack "|" WordStack "}"
 // -------------------------------------------------------------------
```

After executing a transaction, it's necessary to have the effect of the substate log recorded.

-   `#finalizeTx` makes the substate log actually have an effect on the state.

```{.k .uiuck .rvk}
    syntax InternalOp ::= #finalizeTx ( Bool )
 // ------------------------------------------
    rule <k> #finalizeTx(true) => . ... </k>
         <selfDestruct> .Set </selfDestruct>

    rule <k> #finalizeTx(false => true) ... </k>
         <mode> VMTESTS </mode>
         <id> ACCT </id>
         <refund> BAL => 0 </refund>
         <account>
           <acctID> ACCT </acctID>
           <balance> CURRBAL => CURRBAL +Word BAL </balance>
           ...
         </account>

    rule <k> (.K => #newAccount MINER) ~> #finalizeTx(_)... </k>
         <mode> NORMAL </mode>
         <coinbase> MINER </coinbase>
         <activeAccounts> ACCTS </activeAccounts>
      requires notBool MINER in ACCTS

    rule <k> #finalizeTx(false) ... </k>
         <mode> NORMAL </mode>
         <gas> GAVAIL => G*(GAVAIL, GLIMIT, REFUND) </gas>
         <refund> REFUND => 0 </refund>
         <txPending> ListItem(MsgId:Int) ...</txPending>
         <msgID> MsgId </msgID>
         <txGasLimit> GLIMIT </txGasLimit>
         requires REFUND =/=Int 0

    rule <k> #finalizeTx(false => true) ... </k>
         <mode> NORMAL </mode>
         <origin> ORG </origin>
         <coinbase> MINER </coinbase>
         <gas> GAVAIL </gas>
         <refund> 0 </refund>
         <account>
           <acctID> ORG </acctID>
           <balance> ORGBAL => ORGBAL +Int GAVAIL *Int GPRICE </balance>
           ...
         </account>
         <account>
           <acctID> MINER </acctID>
           <balance> MINBAL => MINBAL +Int (GLIMIT -Int GAVAIL) *Int GPRICE </balance>
           ...
         </account>
         <txPending> ListItem(TXID:Int) => .List ... </txPending>
         <message>
           <msgID> TXID </msgID>
           <txGasLimit> GLIMIT </txGasLimit>
           <txGasPrice> GPRICE </txGasPrice>
           ...
         </message>

    rule <k> #finalizeTx(true) ... </k>
         <selfDestruct> ... (SetItem(ACCT) => .Set) </selfDestruct>
         <activeAccounts> ... (SetItem(ACCT) => .Set) </activeAccounts>
         <accounts>
           ( <account>
               <acctID> ACCT </acctID>
               ...
             </account>
          => .Bag
           )
           ...
         </accounts>
```

EVM Programs
============

Lists of opcodes form programs.
Deciding if an opcode is in a list will be useful for modeling gas, and converting a program into a map of program-counter to opcode is useful for execution.

Note that `_in_` ignores the arguments to operators that are parametric.

```{.k .uiuck .rvk}
    syntax OpCodes ::= ".OpCodes" | OpCode ";" OpCodes
 // --------------------------------------------------

    syntax Map ::= #asMapOpCodes ( OpCodes )       [function]
                 | #asMapOpCodes ( Int , OpCodes ) [function, klabel(#asMapOpCodesAux)]
 // -----------------------------------------------------------------------------------
    rule #asMapOpCodes( OPS:OpCodes )         => #asMapOpCodes(0, OPS)
    rule #asMapOpCodes( N , .OpCodes )        => .Map
    rule #asMapOpCodes( N , OP:OpCode ; OCS ) => (N |-> OP) #asMapOpCodes(N +Int 1, OCS) requires notBool isPushOp(OP)
    rule #asMapOpCodes( N , PUSH(M, W) ; OCS) => (N |-> PUSH(M, W)) #asMapOpCodes(N +Int 1 +Int M, OCS)

    syntax OpCodes ::= #asOpCodes ( Map )       [function]
                     | #asOpCodes ( Int , Map ) [function, klabel(#asOpCodesAux)]
 // -----------------------------------------------------------------------------
    rule #asOpCodes(M) => #asOpCodes(0, M)
    rule #asOpCodes(N, .Map) => .OpCodes
    rule #asOpCodes(N, N |-> OP         M) => OP         ; #asOpCodes(N +Int 1,        M) requires notBool isPushOp(OP)
    rule #asOpCodes(N, N |-> PUSH(S, W) M) => PUSH(S, W) ; #asOpCodes(N +Int 1 +Int S, M)

    syntax Int ::= #sizeOpCodeMap ( Map ) [function]
 // ------------------------------------------------
    rule #sizeOpCodeMap(M) => #sizeWordStack(#asmOpCodes(#asOpCodes(M)))
```

EVM OpCodes
-----------

Each subsection has a different class of opcodes.
Organization is based roughly on what parts of the execution state are needed to compute the result of each operator.
This sometimes corresponds to the organization in the yellowpaper.

### Internal Operations

These are just used by the other operators for shuffling local execution state around on the EVM.

-   `#push` will push an element to the `wordStack` without any checks.
-   `#setStack_` will set the current stack to the given one.

```{.k .uiuck .rvk}
    syntax InternalOp ::= "#push" | "#setStack" WordStack
 // -----------------------------------------------------
    rule <k> W0:Int ~> #push => . ... </k> <wordStack> WS => W0 : WS </wordStack>
    rule <k> #setStack WS    => . ... </k> <wordStack> _  => WS      </wordStack>
```

-   `#newAccount_` allows declaring a new empty account with the given address (and assumes the rounding to 160 bits has already occured).

```{.k .uiuck .rvk}
    syntax InternalOp ::= "#newAccount" Int
 // ---------------------------------------
    rule <k> #newAccount ACCT => . ... </k>
         <activeAccounts> ACCTS </activeAccounts>
      requires ACCT in ACCTS

    rule <k> #newAccount ACCT => . ... </k>
         <activeAccounts> ACCTS (.Set => SetItem(ACCT)) </activeAccounts>
         <accounts>
           ( .Bag
          => <account>
               <acctID>  ACCT          </acctID>
               <balance> 0             </balance>
               <code>    .Map          </code>
               <storage> .Map          </storage>
               <acctMap> "nonce" |-> 0 </acctMap>
             </account>
           )
           ...
         </accounts>
      requires notBool ACCT in ACCTS
```

-   `#transferFunds` moves money from one account into another, creating the destination account if it doesn't exist.

```{.k .uiuck .rvk}
    syntax InternalOp ::= "#transferFunds" Int Int Int
 // --------------------------------------------------
    rule <k> #transferFunds ACCTFROM ACCTTO VALUE => . ... </k>
         <account>
           <acctID> ACCTFROM </acctID>
           <balance> ORIGFROM => ORIGFROM -Word VALUE </balance>
           ...
         </account>
         <account>
           <acctID> ACCTTO </acctID>
           <balance> ORIGTO => ORIGTO +Word VALUE </balance>
           ...
         </account>
      requires ACCTFROM =/=K ACCTTO andBool VALUE <=Int ORIGFROM

    rule <k> #transferFunds ACCTFROM ACCTTO VALUE => #exception ... </k>
         <account>
           <acctID> ACCTFROM </acctID>
           <balance> ORIGFROM </balance>
           ...
         </account>
      requires ACCTFROM =/=K ACCTTO andBool VALUE >Int ORIGFROM

    rule <k> (. => #newAccount ACCTTO) ~> #transferFunds ACCTFROM ACCTTO VALUE ... </k>
         <activeAccounts> ACCTS </activeAccounts>
      requires ACCTFROM =/=K ACCTTO andBool notBool ACCTTO in ACCTS

    rule <k> #transferFunds ACCT ACCT _ => . ... </k>
```

### Invalid Operator

We use `INVALID(_)` both for marking the designated invalid operator and for garbage bytes in the input program.

```{.k .uiuck .rvk}
    syntax InvalidOp ::= INVALID ( Int )
 // ------------------------------------
```

### Stack Manipulations

Some operators don't calculate anything, they just push the stack around a bit.

```{.k .uiuck .rvk}
    syntax UnStackOp ::= "POP"
 // --------------------------
    rule <k> POP W => . ... </k>

    syntax StackOp ::= DUP ( Int ) | SWAP ( Int )
 // ---------------------------------------------
    rule <k> DUP(N)  WS:WordStack => #setStack ((WS [ N -Int 1 ]) : WS)                      ... </k>
    rule <k> SWAP(N) (W0 : WS)    => #setStack ((WS [ N -Int 1 ]) : (WS [ N -Int 1 := W0 ])) ... </k>

    syntax PushOp ::= PUSH ( Int , Int )
 // ------------------------------------
    rule <k> PUSH(_, W) => W ~> #push ... </k>
```

### Local Memory

These operations are getters/setters of the local execution memory.

```{.k .uiuck .rvk}
    syntax UnStackOp ::= "MLOAD"
 // ----------------------------
    rule <k> MLOAD INDEX => #asWord(#range(LM, INDEX, 32)) ~> #push ... </k>
         <localMem> LM </localMem>

    syntax BinStackOp ::= "MSTORE" | "MSTORE8"
 // ------------------------------------------
    rule <k> MSTORE INDEX VALUE => . ... </k>
         <localMem> LM => LM [ INDEX := #padToWidth(32, #asByteStack(VALUE)) ] </localMem>

    rule <k> MSTORE8 INDEX VALUE => . ... </k>
         <localMem> LM => LM [ INDEX <- (VALUE %Int 256) ]    </localMem>
```

### Expressions

Expression calculations are simple and don't require anything but the arguments from the `wordStack` to operate.

NOTE: We have to call the opcode `OR` by `EVMOR` instead, because K has trouble parsing it/compiling the definition otherwise.

```{.k .uiuck .rvk}
    syntax UnStackOp ::= "ISZERO" | "NOT"
 // -------------------------------------
    rule <k> ISZERO 0 => 1        ~> #push ... </k>
    rule <k> ISZERO W => 0        ~> #push ... </k> requires W =/=K 0
    rule <k> NOT    W => ~Word W  ~> #push ... </k>

    syntax BinStackOp ::= "ADD" | "MUL" | "SUB" | "DIV" | "EXP" | "MOD"
 // -------------------------------------------------------------------
    rule <k> ADD W0 W1 => W0 +Word W1 ~> #push ... </k>
    rule <k> MUL W0 W1 => W0 *Word W1 ~> #push ... </k>
    rule <k> SUB W0 W1 => W0 -Word W1 ~> #push ... </k>
    rule <k> DIV W0 W1 => W0 /Word W1 ~> #push ... </k>
    rule <k> EXP W0 W1 => W0 ^Word W1 ~> #push ... </k>
    rule <k> MOD W0 W1 => W0 %Word W1 ~> #push ... </k>

    syntax BinStackOp ::= "SDIV" | "SMOD"
 // -------------------------------------
    rule <k> SDIV W0 W1 => W0 /sWord W1 ~> #push ... </k>
    rule <k> SMOD W0 W1 => W0 %sWord W1 ~> #push ... </k>

    syntax TernStackOp ::= "ADDMOD" | "MULMOD"
 // ------------------------------------------
    rule <k> ADDMOD W0 W1 W2 => (W0 +Int W1) %Word W2 ~> #push ... </k>
    rule <k> MULMOD W0 W1 W2 => (W0 *Int W1) %Word W2 ~> #push ... </k>

    syntax BinStackOp ::= "BYTE" | "SIGNEXTEND"
 // -------------------------------------------
    rule <k> BYTE INDEX W     => byte(INDEX, W)     ~> #push ... </k>
    rule <k> SIGNEXTEND W0 W1 => signextend(W0, W1) ~> #push ... </k>

    syntax BinStackOp ::= "AND" | "EVMOR" | "XOR"
 // ---------------------------------------------
    rule <k> AND   W0 W1 => W0 &Word W1   ~> #push ... </k>
    rule <k> EVMOR W0 W1 => W0 |Word W1   ~> #push ... </k>
    rule <k> XOR   W0 W1 => W0 xorWord W1 ~> #push ... </k>

    syntax BinStackOp ::= "LT" | "GT" | "EQ"
 // ----------------------------------------
    rule <k> LT W0 W1 => 1 ~> #push ... </k>  requires W0 <Int   W1
    rule <k> LT W0 W1 => 0 ~> #push ... </k>  requires W0 >=Int  W1
    rule <k> GT W0 W1 => 1 ~> #push ... </k>  requires W0 >Int   W1
    rule <k> GT W0 W1 => 0 ~> #push ... </k>  requires W0 <=Int  W1
    rule <k> EQ W0 W1 => 1 ~> #push ... </k>  requires W0 ==Int  W1
    rule <k> EQ W0 W1 => 0 ~> #push ... </k>  requires W0 =/=Int W1

    syntax BinStackOp ::= "SLT" | "SGT"
 // -----------------------------------
    rule <k> SLT W0 W1 => W0 s<Word W1 ~> #push ... </k>
    rule <k> SGT W0 W1 => W1 s<Word W0 ~> #push ... </k>

    syntax BinStackOp ::= "SHA3"
 // ----------------------------
    rule <k> SHA3 MEMSTART MEMWIDTH => keccak(#range(LM, MEMSTART, MEMWIDTH)) ~> #push ... </k>
         <localMem> LM </localMem>
```

### Local State

These operators make queries about the current execution state.

```{.k .uiuck .rvk}
    syntax NullStackOp ::= "PC" | "GAS" | "GASPRICE" | "GASLIMIT"
 // -------------------------------------------------------------
    rule <k> PC       => PCOUNT ~> #push ... </k> <pc> PCOUNT </pc>
    rule <k> GAS      => GAVAIL ~> #push ... </k> <gas> GAVAIL </gas>
    rule <k> GASPRICE => GPRICE ~> #push ... </k> <gasPrice> GPRICE </gasPrice>
    rule <k> GASLIMIT => GLIMIT ~> #push ... </k> <gasLimit> GLIMIT </gasLimit>

    syntax NullStackOp ::= "COINBASE" | "TIMESTAMP" | "NUMBER" | "DIFFICULTY"
 // -------------------------------------------------------------------------
    rule <k> COINBASE   => CB   ~> #push ... </k> <coinbase> CB </coinbase>
    rule <k> TIMESTAMP  => TS   ~> #push ... </k> <timestamp> TS </timestamp>
    rule <k> NUMBER     => NUMB ~> #push ... </k> <number> NUMB </number>
    rule <k> DIFFICULTY => DIFF ~> #push ... </k> <difficulty> DIFF </difficulty>

    syntax NullStackOp ::= "ADDRESS" | "ORIGIN" | "CALLER" | "CALLVALUE"
 // --------------------------------------------------------------------
    rule <k> ADDRESS   => ACCT ~> #push ... </k> <id> ACCT </id>
    rule <k> ORIGIN    => ORG  ~> #push ... </k> <origin> ORG </origin>
    rule <k> CALLER    => CL   ~> #push ... </k> <caller> CL </caller>
    rule <k> CALLVALUE => CV   ~> #push ... </k> <callValue> CV </callValue>

    syntax NullStackOp ::= "MSIZE" | "CODESIZE"
 // -------------------------------------------
    rule <k> MSIZE    => 32 *Word MU         ~> #push ... </k> <memoryUsed> MU </memoryUsed>
    rule <k> CODESIZE => #sizeOpCodeMap(PGM) ~> #push ... </k> <program> PGM </program>

    syntax TernStackOp ::= "CODECOPY"
 // ---------------------------------
    rule <k> CODECOPY MEMSTART PGMSTART WIDTH => . ... </k>
         <program> PGM </program>
         <localMem> LM => LM [ MEMSTART := #asmOpCodes(#asOpCodes(PGM)) [ PGMSTART .. WIDTH ] ] </localMem>

    syntax UnStackOp ::= "BLOCKHASH"
 // --------------------------------
    rule <k> BLOCKHASH N => #if N >=Int HI orBool HI -Int 256 >Int N #then 0 #else #parseHexWord(Keccak256(Int2String(N))) #fi ~> #push ... </k> <number> HI </number>
```

### `JUMP*`

The `JUMP*` family of operations affect the current program counter.

```{.k .uiuck .rvk}
    syntax NullStackOp ::= "JUMPDEST"
 // ---------------------------------
    rule <k> JUMPDEST => . ... </k>

    syntax UnStackOp ::= "JUMP"
 // ---------------------------
    rule <k> JUMP DEST => . ... </k> <pc> _ => DEST </pc>

    syntax BinStackOp ::= "JUMPI"
 // -----------------------------
    rule <k> JUMPI DEST I => . ... </k> <pc> _      => DEST          </pc> requires I =/=K 0
    rule <k> JUMPI DEST 0 => . ... </k> <pc> PCOUNT => PCOUNT +Int 1 </pc>
```

### `STOP` and `RETURN`

```{.k .uiuck .rvk}
    syntax NullStackOp ::= "STOP"
 // -----------------------------
    rule <k> STOP => #end ... </k>

    syntax BinStackOp ::= "RETURN"
 // ------------------------------
    rule <mode> EXECMODE </mode>
         <k> RETURN RETSTART RETWIDTH => #end ... </k>
         <callDepth> CD => CD -Int 1 </callDepth>
         <output> _ => #range(LM, RETSTART, RETWIDTH) </output>
         <localMem> LM </localMem>
      requires (EXECMODE ==K VMTESTS) orBool (CD >Int 0)
```

### Call Data

These operators query about the current `CALL*` state.

```{.k .uiuck .rvk}
    syntax NullStackOp ::= "CALLDATASIZE"
 // -------------------------------------
    rule <k> CALLDATASIZE => #sizeWordStack(CD) ~> #push ... </k>
         <callData> CD </callData>

    syntax UnStackOp ::= "CALLDATALOAD"
 // -----------------------------------
    rule <k> CALLDATALOAD DATASTART => #asWord(CD [ DATASTART .. 32 ]) ~> #push ... </k>
         <callData> CD </callData>

    syntax TernStackOp ::= "CALLDATACOPY"
 // -------------------------------------
    rule <k> CALLDATACOPY MEMSTART DATASTART DATAWIDTH => . ... </k>
         <localMem> LM => LM [ MEMSTART := CD [ DATASTART .. DATAWIDTH ] ] </localMem>
         <callData> CD </callData>
```

### Log Operations

```{.k .uiuck .rvk}
    syntax BinStackOp ::= LogOp
    syntax LogOp ::= LOG ( Int )
 // ----------------------------
    rule <k> LOG(N) MEMSTART MEMWIDTH => . ... </k>
         <id> ACCT </id>
         <wordStack> WS => #drop(N, WS) </wordStack>
         <localMem> LM </localMem>
         <log> ... (.Set => SetItem({ ACCT | #take(N, WS) | #range(LM, MEMSTART, MEMWIDTH) })) </log>
      requires #sizeWordStack(WS) >=Int N
```

Ethereum Network OpCodes
------------------------

Operators that require access to the rest of the Ethereum network world-state can be taken as a first draft of a "blockchain generic" language.

### Account Queries

TODO: It's unclear what to do in the case of an account not existing for these operators.
`BALANCE` is specified to push 0 in this case, but the others are not specified.
For now, I assume that they instantiate an empty account and use the empty data.

```{.k .uiuck .rvk}
    syntax UnStackOp ::= "BALANCE"
 // ------------------------------
    rule <k> BALANCE ACCT => BAL ~> #push ... </k>
         <account>
           <acctID> ACCT </acctID>
           <balance> BAL </balance>
           ...
         </account>

    rule <k> BALANCE ACCT => #newAccount ACCT ~> 0 ~> #push ... </k>
         <activeAccounts> ACCTS </activeAccounts>
      requires notBool ACCT in ACCTS

    syntax UnStackOp ::= "EXTCODESIZE"
 // ----------------------------------
    rule <k> EXTCODESIZE ACCT => #sizeOpCodeMap(CODE) ~> #push ... </k>
         <account>
           <acctID> ACCT </acctID>
           <code> CODE </code>
           ...
         </account>

    rule <k> EXTCODESIZE ACCT => #newAccount ACCT ~> 0 ~> #push ... </k>
         <activeAccounts> ACCTS </activeAccounts>
      requires notBool ACCT in ACCTS
```

TODO: What should happen in the case that the account doesn't exist with `EXTCODECOPY`?
Should we pad zeros (for the copied "program")?

```{.k .uiuck .rvk}
    syntax QuadStackOp ::= "EXTCODECOPY"
 // ------------------------------------
    rule <k> EXTCODECOPY ACCT MEMSTART PGMSTART WIDTH => . ... </k>
         <localMem> LM => LM [ MEMSTART := #asmOpCodes(#asOpCodes(PGM)) [ PGMSTART .. WIDTH ] ] </localMem>
         <account>
           <acctID> ACCT </acctID>
           <code> PGM </code>
           ...
         </account>

    rule <k> EXTCODECOPY ACCT MEMSTART PGMSTART WIDTH => #newAccount ACCT ... </k>
         <activeAccounts> ACCTS </activeAccounts>
      requires notBool ACCT in ACCTS
```

### Account Storage Operations

These operations interact with the account storage.

```{.k .uiuck .rvk}
    syntax UnStackOp ::= "SLOAD"
 // ----------------------------
    rule <k> SLOAD INDEX => 0 ~> #push ... </k>
         <id> ACCT </id>
         <account>
           <acctID> ACCT </acctID>
           <storage> STORAGE </storage>
           ...
         </account> requires notBool INDEX in_keys(STORAGE)

    rule <k> SLOAD INDEX => VALUE ~> #push ... </k>
         <id> ACCT </id>
         <account>
           <acctID> ACCT </acctID>
           <storage> ... INDEX |-> VALUE ... </storage>
           ...
         </account>

    syntax BinStackOp ::= "SSTORE"
 // ------------------------------
    rule <k> SSTORE INDEX VALUE => . ... </k>
         <id> ACCT </id>
         <account>
           <acctID> ACCT </acctID>
           <storage> ... (INDEX |-> (OLD => VALUE)) ... </storage>
           ...
         </account>
         <refund> R => #ifInt OLD =/=Int 0 andBool VALUE ==Int 0
                        #then R +Word Rsstoreclear < SCHED >
                        #else R
                       #fi
         </refund>
         <schedule> SCHED </schedule>

    rule <k> SSTORE INDEX VALUE => . ... </k>
         <id> ACCT </id>
         <account>
           <acctID> ACCT </acctID>
           <storage> STORAGE => STORAGE [ INDEX <- VALUE ] </storage>
           ...
         </account>
      requires notBool (INDEX in_keys(STORAGE))
```

### Call Operations

The various `CALL*` (and other inter-contract control flow) operations will be desugared into these `InternalOp`s.

-   The `callLog` is used to store the `CALL*`/`CREATE` operations so that we can compare them against the test-set.

```{.k .uiuck .rvk}
    syntax Call ::= "{" Int "|" Int "|" Int "|" WordStack "}"
 // ---------------------------------------------------------
```

-   `#call_____` takes the calling account, the account to execute as, the account whose code should execute, the gas limit, the amount to transfer, and the arguments.
-   `#callWithCode______` takes the calling account, the accout to execute as, the code to execute (as a map), the gas limit, the amount to transfer, and the arguments.
-   `#return__` is a placeholder for the calling program, specifying where to place the returned data in memory.

```{.k .uiuck .rvk}
    syntax InternalOp ::= "#call" Int Int Int Int Int Int WordStack
                        | "#callWithCode" Int Int Map Int Int Int WordStack
                        | "#mkCall" Int Int Map Int Int Int WordStack
 // -------------------------------------------------------------
    rule <k> #call ACCTFROM ACCTTO ACCTCODE GLIMIT VALUE APPVALUE ARGS
          => #callWithCode ACCTFROM ACCTTO (0 |-> #precompiled(ACCTCODE)) GLIMIT VALUE APPVALUE ARGS
         ...
         </k>
      requires ACCTTO >Int 0 andBool ACCTTO <=Int 4

    rule <k> #call ACCTFROM ACCTTO ACCTCODE GLIMIT VALUE APPVALUE ARGS
          => #callWithCode ACCTFROM ACCTTO CODE GLIMIT VALUE APPVALUE ARGS
         ...
         </k>
         <acctID> ACCTCODE </acctID>
         <code> CODE </code>
      requires notBool (ACCTTO >Int 0 andBool ACCTTO <=Int 4)

    rule <schedule> SCHED </schedule>
         <k> #callWithCode ACCTFROM ACCTTO CODE GLIMIT VALUE APPVALUE ARGS
          => #pushCallStack ~> #pushWorldState
          ~> #transferFunds ACCTFROM ACCTTO VALUE
          ~> #mkCall ACCTFROM ACCTTO CODE GLIMIT VALUE APPVALUE ARGS
         ...
         </k>
         <callDepth> CD </callDepth>
      requires CD <Int 1024

    rule <k> #callWithCode _ _ _ _ _ _ _ => #pushCallStack ~> #pushWorldState ~> #exception ... </k>
         <callDepth> CD </callDepth>
      requires CD >=Int 1024

    rule <mode> EXECMODE </mode>
         <k> #mkCall ACCTFROM ACCTTO CODE GLIMIT VALUE APPVALUE ARGS
          => #initVM ~> #if EXECMODE ==K VMTESTS #then #end #else #execute #fi
         ...
         </k>
         <callLog> ... (.Set => SetItem({ ACCTTO | GLIMIT | VALUE | ARGS })) </callLog>
         <callDepth> CD => CD +Int 1 </callDepth>
         <callData> _ => ARGS </callData>
         <callValue> _ => APPVALUE </callValue>
         <id> _ => ACCTTO </id>
         <gas> _ => GLIMIT </gas>
         <caller> _ => ACCTFROM </caller>
         <program> _ => CODE </program>

    syntax KItem ::= "#initVM"
 // --------------------------
    rule <k> #initVM    => . ...      </k>
         <pc>         _ => 0          </pc>
         <memoryUsed> _ => 0          </memoryUsed>
         <output>     _ => .WordStack </output>
         <wordStack>  _ => .WordStack </wordStack>
         <localMem>   _ => .Map       </localMem>

    syntax KItem ::= "#return" Int Int
 // ----------------------------------
    rule <k> #exception ~> #return _ _
          => #popCallStack ~> #popWorldState  ~> 0 ~> #push
         ...
         </k>

    rule <mode> EXECMODE </mode>
         <k> #end ~> #return RETSTART RETWIDTH
          => #popCallStack
          ~> #if EXECMODE ==K VMTESTS #then #popWorldState #else #dropWorldState #fi
          ~> 1 ~> #push ~> #refund GAVAIL ~> #setLocalMem RETSTART RETWIDTH OUT
         ...
         </k>
         <output> OUT </output>
         <gas> GAVAIL </gas>

    syntax InternalOp ::= "#refund" Int
                        | "#setLocalMem" Int Int WordStack
 // ------------------------------------------------------
    rule <k> #refund G => . ... </k> <gas> GAVAIL => GAVAIL +Int G </gas>

    rule <k> #setLocalMem START WIDTH WS => . ... </k>
         <localMem> LM => LM [ START := #take(minInt(WIDTH, #sizeWordStack(WS)), WS) ] </localMem>
```

-   `#precompiled` is a placeholder for the 4 pre-compiled contracts at addresses 1 through 4.

```{.k .uiuck .rvk}
    syntax InternalOp ::= #precompiled ( Int )
 // ------------------------------------------
```

For each `CALL*` operation, we make a corresponding call to `#call` and a state-change to setup the custom parts of the calling environment.

```{.k .uiuck .rvk}
    syntax CallOp ::= "CALL"
 // ------------------------
    rule <k> CALL GCAP ACCTTO VALUE ARGSTART ARGWIDTH RETSTART RETWIDTH
          => #call ACCTFROM ACCTTO ACCTTO Ccallgas(SCHED, ACCTTO, ACCTS, GCAP, GAVAIL, VALUE) VALUE VALUE #range(LM, ARGSTART, ARGWIDTH)
          ~> #return RETSTART RETWIDTH
         ...
         </k>
         <schedule> SCHED </schedule>
         <id> ACCTFROM </id>
         <localMem> LM </localMem>
         <activeAccounts> ACCTS </activeAccounts>
         <previousGas> GAVAIL </previousGas>

    syntax CallOp ::= "CALLCODE"
 // ----------------------------
    rule <k> CALLCODE GCAP ACCTTO VALUE ARGSTART ARGWIDTH RETSTART RETWIDTH
          => #call ACCTFROM ACCTFROM ACCTTO Ccallgas(SCHED, ACCTTO, ACCTS, GCAP, GAVAIL, VALUE) VALUE VALUE #range(LM, ARGSTART, ARGWIDTH)
          ~> #return RETSTART RETWIDTH
         ...
         </k>
         <schedule> SCHED </schedule>
         <id> ACCTFROM </id>
         <localMem> LM </localMem>
         <activeAccounts> ACCTS </activeAccounts>
         <previousGas> GAVAIL </previousGas>

    syntax CallSixOp ::= "DELEGATECALL"
 // -----------------------------------
    rule <k> DELEGATECALL GCAP ACCTTO ARGSTART ARGWIDTH RETSTART RETWIDTH
          => #call ACCTFROM ACCTFROM ACCTTO GCAP 0 VALUE #range(LM, ARGSTART, ARGWIDTH)
          ~> #return RETSTART RETWIDTH
         ...
         </k>
         <id> ACCTFROM </id>
         <callValue> VALUE </callValue>
         <localMem> LM </localMem>
```

### Account Creation/Deletion

-   `#create____` transfers the endowment to the new account and triggers the execution of the initialization code.
-   `#codeDeposit_` checks the result of initialization code and whether the code deposit can be paid, indicating an error if not.

```{.k .uiuck .rvk}
    syntax InternalOp ::= "#create" Int Int Int Int Map
    syntax KItem      ::= "#mkCreate" Int Map Int Int
 // -------------------------------------------------
    rule <k> #create ACCTFROM ACCTTO GAVAIL VALUE INITCODE
          => #pushCallStack ~> #pushWorldState
          ~> #transferFunds ACCTFROM ACCTTO VALUE
          ~> #mkCreate ACCTFROM INITCODE GAVAIL VALUE
         ...
         </k>
         <callDepth> CD </callDepth>
      requires CD <Int 1024

    rule <k> #exception ~> #mkCreate _ _ GAVAIL _ => #exception ... </k> <gas> _ => GAVAIL </gas>

    rule <k> #create _ _ _ _ _ => #pushCallStack ~> #pushWorldState ~> #exception ... </k>
         <callDepth> CD </callDepth>
      requires CD >=Int 1024

    rule <mode> EXECMODE </mode>
         <k> #mkCreate ACCTFROM INITCODE GAVAIL VALUE
          => #initVM ~> #if EXECMODE ==K VMTESTS #then #end #else #execute #fi
         ...
         </k>
         <id> ACCT </id>
         <gas> OLDGAVAIL => GAVAIL </gas>
         <program> _ => INITCODE </program>
         <caller> _ => ACCTFROM </caller>
         <callLog> ... (.Set => SetItem({ 0 | OLDGAVAIL +Int GAVAIL | VALUE | #asmOpCodes(#asOpCodes(INITCODE)) })) </callLog>
         <callDepth> CD => CD +Int 1 </callDepth>
         <callData> _ => .WordStack </callData>
         <callValue> _ => VALUE </callValue>
         <account>
           <acctID> ACCT </acctID>
           <acctMap> ... "nonce" |-> (NONCE => NONCE +Int 1) ... </acctMap>
          ...
         </account>

    syntax KItem ::= "#codeDeposit" Int
                   | "#mkCodeDeposit" Int
                   | "#finishCodeDeposit"
 // -------------------------------------
    rule <k> #exception ~> #codeDeposit _ => #popCallStack ~> #popWorldState ~> #refund GAVAIL ~> 0 ~> #push ... </k>
         <gas> GAVAIL </gas>

    rule <mode> EXECMODE </mode>
         <k> #end ~> #codeDeposit ACCT => #mkCodeDeposit ACCT ~> ACCT ~> #push ...</k>

    rule <k> #mkCodeDeposit ACCT => #if EXECMODE ==K VMTESTS #then . #else Gcodedeposit < SCHED > *Int #sizeWordStack(OUT) ~> #deductGas #fi ~> #finishCodeDeposit ...</k>
         <mode> EXECMODE </mode>
         <schedule> SCHED </schedule>
         <output> OUT => .WordStack </output>
         <account>
           <acctID> ACCT </acctID>
           <code> _ => #asMapOpCodes(#dasmOpCodes(OUT)) </code>
           ...
         </account>
    rule <k> #finishCodeDeposit => #popCallStack ~> #if EXECMODE ==K VMTESTS #then #popWorldState #else #dropWorldState #fi ~> #refund GAVAIL ...</k>
         <mode> EXECMODE </mode>
         <gas> GAVAIL </gas>
```

`CREATE` will attempt to `#create` the account using the initialization code and cleans up the result with `#codeDeposit`.

```{.k .uiuck .rvk}
    syntax TernStackOp ::= "CREATE"
 // -------------------------------
    rule <k> CREATE VALUE MEMSTART MEMWIDTH
          => #create ACCT #newAddr(ACCT, NONCE) #allBut64th(GAVAIL) VALUE #asMapOpCodes(#dasmOpCodes(#range(LM, MEMSTART, MEMWIDTH)))
          ~> #codeDeposit #newAddr(ACCT, NONCE)
         ...
         </k>
         <id> ACCT </id>
         <gas> GAVAIL => GAVAIL /Int 64 </gas>
         <localMem> LM </localMem>
         <activeAccounts> ACCTS </activeAccounts>
         <account>
           <acctID> ACCT </acctID>
           <acctMap> ... "nonce" |-> NONCE ... </acctMap>
           ...
         </account>
```

`SELFDESTRUCT` marks the current account for deletion and transfers funds out of the current account.

```{.k .uiuck .rvk}
    syntax UnStackOp ::= "SELFDESTRUCT"
 // -----------------------------------
    rule <k> SELFDESTRUCT ACCTTO => #transferFunds ACCT ACCTTO BALFROM ~> #end ... </k>
         <schedule> SCHED </schedule>
         <id> ACCT </id>
         <selfDestruct> SDS (.Set => SetItem(ACCT)) </selfDestruct>
         <refund> RF => #ifInt ACCT in SDS #then RF #else RF +Word Rselfdestruct < SCHED > #fi </refund>
         <account>
           <acctID> ACCT </acctID>
           <balance> BALFROM </balance>
           ...
         </account>
```

Ethereum Gas Calculation
========================

The gas calculation is designed to mirror the style of the yellowpaper.
Gas is consumed either by increasing the amount of memory being used, or by executing opcodes.

Memory Consumption
------------------

Memory consumed is tracked to determine the appropriate amount of gas to charge for each operation.
In the yellowpaper, each opcode is defined to consume zero gas unless specified otherwise next to the semantics of the opcode (appendix H).

-   `#memory` computes the new memory size given the old size and next operator (with its arguments).
-   `#memoryUsageUpdate` is the function `M` in appendix H of the yellowpaper which helps track the memory used.

```{.k .uiuck .rvk}
    syntax Int ::= #memory ( OpCode , Int ) [function]
 // --------------------------------------------------
    rule #memory ( MLOAD INDEX     , MU ) => #memoryUsageUpdate(MU, INDEX, 32)
    rule #memory ( MSTORE INDEX _  , MU ) => #memoryUsageUpdate(MU, INDEX, 32)
    rule #memory ( MSTORE8 INDEX _ , MU ) => #memoryUsageUpdate(MU, INDEX, 1)

    rule #memory ( SHA3 START WIDTH   , MU ) => #memoryUsageUpdate(MU, START, WIDTH)
    rule #memory ( LOG(_) START WIDTH , MU ) => #memoryUsageUpdate(MU, START, WIDTH)

    rule #memory ( CODECOPY START _ WIDTH      , MU ) => #memoryUsageUpdate(MU, START, WIDTH)
    rule #memory ( EXTCODECOPY _ START _ WIDTH , MU ) => #memoryUsageUpdate(MU, START, WIDTH)
    rule #memory ( CALLDATACOPY START _ WIDTH  , MU ) => #memoryUsageUpdate(MU, START, WIDTH)

    rule #memory ( CREATE _ START WIDTH , MU ) => #memoryUsageUpdate(MU, START, WIDTH)
    rule #memory ( RETURN START WIDTH   , MU ) => #memoryUsageUpdate(MU, START, WIDTH)

    rule #memory ( COP:CallOp     _ _ _ ARGSTART ARGWIDTH RETSTART RETWIDTH , MU ) => #memoryUsageUpdate(#memoryUsageUpdate(MU, ARGSTART, ARGWIDTH), RETSTART, RETWIDTH)
    rule #memory ( CSOP:CallSixOp _ _   ARGSTART ARGWIDTH RETSTART RETWIDTH , MU ) => #memoryUsageUpdate(#memoryUsageUpdate(MU, ARGSTART, ARGWIDTH), RETSTART, RETWIDTH)
```

Grumble grumble, K sucks at `owise`.

```{.k .uiuck .rvk}
    rule #memory(JUMP _,    MU) => MU
    rule #memory(JUMPI _ _, MU) => MU
    rule #memory(JUMPDEST,  MU) => MU

    rule #memory(SSTORE _ _,   MU) => MU
    rule #memory(SLOAD _,      MU) => MU

    rule #memory(ADD _ _,        MU) => MU
    rule #memory(SUB _ _,        MU) => MU
    rule #memory(MUL _ _,        MU) => MU
    rule #memory(DIV _ _,        MU) => MU
    rule #memory(EXP _ _,        MU) => MU
    rule #memory(MOD _ _,        MU) => MU
    rule #memory(SDIV _ _,       MU) => MU
    rule #memory(SMOD _ _,       MU) => MU
    rule #memory(SIGNEXTEND _ _, MU) => MU
    rule #memory(ADDMOD _ _ _,   MU) => MU
    rule #memory(MULMOD _ _ _,   MU) => MU

    rule #memory(NOT _,     MU) => MU
    rule #memory(AND _ _,   MU) => MU
    rule #memory(EVMOR _ _, MU) => MU
    rule #memory(XOR _ _,   MU) => MU
    rule #memory(BYTE _ _,  MU) => MU
    rule #memory(ISZERO _,  MU) => MU

    rule #memory(LT _ _,         MU) => MU
    rule #memory(GT _ _,         MU) => MU
    rule #memory(SLT _ _,        MU) => MU
    rule #memory(SGT _ _,        MU) => MU
    rule #memory(EQ _ _,         MU) => MU

    rule #memory(POP _,      MU) => MU
    rule #memory(PUSH(_, _), MU) => MU
    rule #memory(DUP(_) _,   MU) => MU
    rule #memory(SWAP(_) _,  MU) => MU

    rule #memory(STOP,         MU) => MU
    rule #memory(ADDRESS,      MU) => MU
    rule #memory(ORIGIN,       MU) => MU
    rule #memory(CALLER,       MU) => MU
    rule #memory(CALLVALUE,    MU) => MU
    rule #memory(CALLDATASIZE, MU) => MU
    rule #memory(CODESIZE,     MU) => MU
    rule #memory(GASPRICE,     MU) => MU
    rule #memory(COINBASE,     MU) => MU
    rule #memory(TIMESTAMP,    MU) => MU
    rule #memory(NUMBER,       MU) => MU
    rule #memory(DIFFICULTY,   MU) => MU
    rule #memory(GASLIMIT,     MU) => MU
    rule #memory(PC,           MU) => MU
    rule #memory(MSIZE,        MU) => MU
    rule #memory(GAS,          MU) => MU

    rule #memory(SELFDESTRUCT _, MU) => MU
    rule #memory(CALLDATALOAD _, MU) => MU
    rule #memory(EXTCODESIZE _,  MU) => MU
    rule #memory(BALANCE _,      MU) => MU
    rule #memory(BLOCKHASH _,    MU) => MU

    syntax Int ::= #memoryUsageUpdate ( Int , Int , Int ) [function]
 // ----------------------------------------------------------------
    rule #memoryUsageUpdate(MU, START, 0)     => MU
    rule #memoryUsageUpdate(MU, START, WIDTH) => maxInt(MU, (START +Int WIDTH) up/Int 32) requires WIDTH >Int 0
```

Execution Gas
-------------

Each opcode has an intrinsic gas cost of execution as well (appendix H of the yellowpaper).

-   `#gasExec` loads all the relevant surronding state and uses that to compute the intrinsic execution gas of each opcode.

```{.k .uiuck .rvk}
    syntax InternalOp ::= #gasExec ( Schedule , OpCode )
 // ----------------------------------------------------
    rule <k> #gasExec(SCHED, SSTORE INDEX VALUE) => Csstore(SCHED, INDEX, VALUE, STORAGE) ... </k>
         <id> ACCT </id>
         <account>
           <acctID> ACCT </acctID>
           <storage> STORAGE </storage>
           ...
         </account>

    rule <k> #gasExec(SCHED, EXP W0 0)  => Gexp < SCHED > ... </k>
    rule <k> #gasExec(SCHED, EXP W0 W1) => Gexp < SCHED > +Int (Gexpbyte < SCHED > *Int (1 +Int (log256Int(W1)))) ... </k> requires W1 =/=K 0

    rule <k> #gasExec(SCHED, CALLDATACOPY  _ _ WIDTH) => Gverylow     < SCHED > +Int (Gcopy < SCHED > *Int (WIDTH up/Int 32)) ... </k>
    rule <k> #gasExec(SCHED, CODECOPY      _ _ WIDTH) => Gverylow     < SCHED > +Int (Gcopy < SCHED > *Int (WIDTH up/Int 32)) ... </k>
    rule <k> #gasExec(SCHED, EXTCODECOPY _ _ _ WIDTH) => Gextcodecopy < SCHED > +Int (Gcopy < SCHED > *Int (WIDTH up/Int 32)) ... </k>

    rule <k> #gasExec(SCHED, LOG(N) _ WIDTH) => (Glog < SCHED > +Int (Glogdata < SCHED > *Int WIDTH) +Int (N *Int Glogtopic < SCHED >)) ... </k>

    rule <k> #gasExec(SCHED, COP:CallOp     GCAP ACCTTO VALUE _ _ _ _) => Ccall(SCHED, ACCTTO, ACCTS, GCAP, GAVAIL, VALUE) ... </k> <activeAccounts> ACCTS </activeAccounts> <gas> GAVAIL </gas>
    rule <k> #gasExec(SCHED, CSOP:CallSixOp GCAP ACCTTO       _ _ _ _) => Ccall(SCHED, ACCTTO, ACCTS, GCAP, GAVAIL, 0)     ... </k> <activeAccounts> ACCTS </activeAccounts> <gas> GAVAIL </gas>

    rule <k> #gasExec(SCHED, SELFDESTRUCT ACCT) => Cselfdestruct(SCHED, ACCT, ACCTS) ... </k> <activeAccounts> ACCTS </activeAccounts>
    rule <k> #gasExec(SCHED, CREATE _ _ _)      => Gcreate < SCHED >                 ... </k>

    rule <k> #gasExec(SCHED, SHA3 _ WIDTH) => Gsha3 < SCHED > +Int (Gsha3word < SCHED > *Int (WIDTH up/Int 32)) ... </k>

    rule <k> #gasExec(SCHED, JUMPDEST) => Gjumpdest < SCHED > ... </k>
    rule <k> #gasExec(SCHED, SLOAD _)  => Gsload    < SCHED > ... </k>

    // Wzero
    rule <k> #gasExec(SCHED, STOP)       => Gzero < SCHED > ... </k>
    rule <k> #gasExec(SCHED, RETURN _ _) => Gzero < SCHED > ... </k>

    // Wbase
    rule <k> #gasExec(SCHED, ADDRESS)      => Gbase < SCHED > ... </k>
    rule <k> #gasExec(SCHED, ORIGIN)       => Gbase < SCHED > ... </k>
    rule <k> #gasExec(SCHED, CALLER)       => Gbase < SCHED > ... </k>
    rule <k> #gasExec(SCHED, CALLVALUE)    => Gbase < SCHED > ... </k>
    rule <k> #gasExec(SCHED, CALLDATASIZE) => Gbase < SCHED > ... </k>
    rule <k> #gasExec(SCHED, CODESIZE)     => Gbase < SCHED > ... </k>
    rule <k> #gasExec(SCHED, GASPRICE)     => Gbase < SCHED > ... </k>
    rule <k> #gasExec(SCHED, COINBASE)     => Gbase < SCHED > ... </k>
    rule <k> #gasExec(SCHED, TIMESTAMP)    => Gbase < SCHED > ... </k>
    rule <k> #gasExec(SCHED, NUMBER)       => Gbase < SCHED > ... </k>
    rule <k> #gasExec(SCHED, DIFFICULTY)   => Gbase < SCHED > ... </k>
    rule <k> #gasExec(SCHED, GASLIMIT)     => Gbase < SCHED > ... </k>
    rule <k> #gasExec(SCHED, POP _)        => Gbase < SCHED > ... </k>
    rule <k> #gasExec(SCHED, PC)           => Gbase < SCHED > ... </k>
    rule <k> #gasExec(SCHED, MSIZE)        => Gbase < SCHED > ... </k>
    rule <k> #gasExec(SCHED, GAS)          => Gbase < SCHED > ... </k>

    // Wverylow
    rule <k> #gasExec(SCHED, ADD _ _)        => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, SUB _ _)        => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, NOT _)          => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, LT _ _)         => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, GT _ _)         => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, SLT _ _)        => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, SGT _ _)        => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, EQ _ _)         => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, ISZERO _)       => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, AND _ _)        => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, EVMOR _ _)      => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, XOR _ _)        => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, BYTE _ _)       => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, CALLDATALOAD _) => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, MLOAD _)        => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, MSTORE _ _)     => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, MSTORE8 _ _)    => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, PUSH(_, _))     => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, DUP(_) _)       => Gverylow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, SWAP(_) _)      => Gverylow < SCHED > ... </k>

    // Wlow
    rule <k> #gasExec(SCHED, MUL _ _)        => Glow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, DIV _ _)        => Glow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, SDIV _ _)       => Glow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, MOD _ _)        => Glow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, SMOD _ _)       => Glow < SCHED > ... </k>
    rule <k> #gasExec(SCHED, SIGNEXTEND _ _) => Glow < SCHED > ... </k>

    // Wmid
    rule <k> #gasExec(SCHED, ADDMOD _ _ _) => Gmid < SCHED > ... </k>
    rule <k> #gasExec(SCHED, MULMOD _ _ _) => Gmid < SCHED > ... </k>
    rule <k> #gasExec(SCHED, JUMP _) => Gmid < SCHED > ... </k>

    // Whigh
    rule <k> #gasExec(SCHED, JUMPI _ _) => Ghigh < SCHED > ... </k>

    rule <k> #gasExec(SCHED, EXTCODESIZE _) => Gextcodesize < SCHED > ... </k>
    rule <k> #gasExec(SCHED, BALANCE _)     => Gbalance     < SCHED > ... </k>
    rule <k> #gasExec(SCHED, BLOCKHASH _)   => Gblockhash   < SCHED > ... </k>
```

There are several helpers for calculating gas (most of them also specified in the yellowpaper).

Note: These are all functions as the operator `#gasExec` has already loaded all the relevant state.

```{.k .uiuck .rvk}
    syntax Int ::= Csstore ( Schedule , Int , Int , Map ) [function]
 // ----------------------------------------------------------------
    rule Csstore(SCHED, INDEX, VALUE, STORAGE) => Gsstoreset < SCHED >   requires VALUE =/=K 0 andBool notBool INDEX in_keys(STORAGE)
    rule Csstore(SCHED, INDEX, VALUE, STORAGE) => Gsstorereset < SCHED > requires VALUE ==K 0  orBool  INDEX in_keys(STORAGE)

    syntax Int ::= Ccall    ( Schedule , Int , Set , Int , Int , Int ) [function]
                 | Ccallgas ( Schedule , Int , Set , Int , Int , Int ) [function]
                 | Cgascap  ( Schedule , Int , Int , Int )             [function]
                 | Cextra   ( Schedule , Int , Set , Int )             [function]
                 | Cxfer    ( Schedule , Int )                         [function]
                 | Cnew     ( Schedule , Int , Set )                   [function]
 // -----------------------------------------------------------------------------
    rule Ccall(SCHED, ACCT, ACCTS, GCAP, GAVAIL, VALUE) => Cextra(SCHED, ACCT, ACCTS, VALUE) +Int Cgascap(SCHED, GCAP, GAVAIL, Cextra(SCHED, ACCT, ACCTS, VALUE))

    rule Ccallgas(SCHED, ACCT, ACCTS, GCAP, GAVAIL, 0)     => Cgascap(SCHED, GCAP, GAVAIL, Cextra(SCHED, ACCT, ACCTS,     0))
    rule Ccallgas(SCHED, ACCT, ACCTS, GCAP, GAVAIL, VALUE) => Cgascap(SCHED, GCAP, GAVAIL, Cextra(SCHED, ACCT, ACCTS, VALUE)) +Int Gcallstipend < SCHED > requires VALUE =/=K 0

    rule Cgascap(SCHED, GCAP, GAVAIL, GEXTRA) => minInt(#allBut64th(GAVAIL -Int GEXTRA), GCAP) requires GAVAIL >=Int GEXTRA andBool notBool Gstaticcalldepth << SCHED >>
    rule Cgascap(SCHED, GCAP, GAVAIL, GEXTRA) => GCAP                                          requires GAVAIL <Int  GEXTRA orBool Gstaticcalldepth << SCHED >>

    rule Cextra(SCHED, ACCT, ACCTS, VALUE) => Gcall < SCHED > +Int Cnew(SCHED, ACCT, ACCTS) +Int Cxfer(SCHED, VALUE)

    rule Cxfer(SCHED, 0) => 0
    rule Cxfer(SCHED, N) => Gcallvalue < SCHED > requires N =/=K 0

    rule Cnew(SCHED, ACCT, ACCTS) => Gnewaccount < SCHED > requires notBool ACCT in ACCTS
    rule Cnew(SCHED, ACCT, ACCTS) => 0                     requires ACCT in ACCTS

    syntax Int ::= Cselfdestruct ( Schedule , Int , Set ) [function]
 // ----------------------------------------------------------------
    rule Cselfdestruct(SCHED, ACCT, ACCTS) => Gselfdestruct < SCHED > +Int Gnewaccount < SCHED > requires (notBool ACCT in ACCTS) andBool (Gselfdestructnewaccount << SCHED >>)
    rule Cselfdestruct(SCHED, ACCT, ACCTS) => Gselfdestruct < SCHED >                            requires (notBool ACCT in ACCTS) andBool (notBool Gselfdestructnewaccount << SCHED >>)
    rule Cselfdestruct(SCHED, ACCT, ACCTS) => Gselfdestruct < SCHED >                            requires ACCT in ACCTS

    syntax Int ::= #allBut64th ( Int ) [function]
 // ---------------------------------------------
    rule #allBut64th(N) => N -Int (N /Int 64)

    syntax Int ::= G0 ( Schedule , WordStack , Bool ) [function]
 // ------------------------------------------------------------
    rule G0(SCHED, .WordStack, true)  => Gtxcreate    < SCHED >
    rule G0(SCHED, .WordStack, false) => Gtransaction < SCHED >

    rule G0(SCHED, 0 : REST, ISCREATE) => Gtxdatazero    < SCHED > +Int G0(SCHED, REST, ISCREATE)
    rule G0(SCHED, N : REST, ISCREATE) => Gtxdatanonzero < SCHED > +Int G0(SCHED, REST, ISCREATE)

    syntax Int ::= "G*" "(" Int "," Int "," Int ")" [function]
 // ----------------------------------------------------------
    rule G*(GAVAIL, GLIMIT, REFUND) => GAVAIL +Int minInt((GLIMIT -Int GAVAIL)/Int 2, REFUND)
```

Fee Schedule from C++ Implementation
------------------------------------

The [C++ Implementation of EVM](https://github.com/ethereum/cpp-ethereum) specifies several different "profiles" for how the VM works.
Here we provide each protocol from the C++ implementation, as the yellowpaper does not contain all the different profiles.
Specify which profile by passing in the argument `-cSCHEDULE=<FEE_SCHEDULE>` when calling `krun` (the available `<FEE_SCHEDULE>` are supplied here).

A `ScheduleFlag` is a boolean determined by the fee schedule; applying a `ScheduleFlag` to a `Schedule` yields whether the flag is set or not.

```{.k .uiuck .rvk}
    syntax Bool ::= ScheduleFlag "<<" Schedule ">>" [function]
 // ----------------------------------------------------------

    syntax ScheduleFlag ::= "Gselfdestructnewaccount" | "Gstaticcalldepth"
 // ----------------------------------------------------------------------
```

A `ScheduleConst` is a constant determined by the fee schedule; applying a `ScheduleConst` to a `Schedule` yields the correct constant for that schedule.

```{.k .uiuck .rvk}
    syntax Int ::= ScheduleConst "<" Schedule ">" [function]
 // --------------------------------------------------------

    syntax ScheduleConst ::= "Gzero"        | "Gbase"        | "Gverylow"      | "Glow"           | "Gmid"         | "Ghigh"
                           | "Gextcodesize" | "Gextcodecopy" | "Gbalance"      | "Gsload"         | "Gjumpdest"    | "Gsstoreset"
                           | "Gsstorereset" | "Rsstoreclear" | "Rselfdestruct" | "Gselfdestruct"  | "Gcreate"      | "Gcodedeposit"
                           | "Gcall"        | "Gcallvalue"   | "Gcallstipend"  | "Gnewaccount"    | "Gexp"         | "Gexpbyte"
                           | "Gmemory"      | "Gtxcreate"    | "Gtxdatazero"   | "Gtxdatanonzero" | "Gtransaction" | "Glog"
                           | "Glogdata"     | "Glogtopic"    | "Gsha3"         | "Gsha3word"      | "Gcopy"        | "Gblockhash"   | "Gquadcoeff"
 // ----------------------------------------------------------------------------------------------------------------------------------------------
```

### Defualt Schedule

```{.k .uiuck .rvk}
    syntax Schedule ::= "DEFAULT"
 // -----------------------------
    rule Gzero    < DEFAULT > => 0
    rule Gbase    < DEFAULT > => 2
    rule Gverylow < DEFAULT > => 3
    rule Glow     < DEFAULT > => 5
    rule Gmid     < DEFAULT > => 8
    rule Ghigh    < DEFAULT > => 10

    rule Gexp      < DEFAULT > => 10
    rule Gexpbyte  < DEFAULT > => 10
    rule Gsha3     < DEFAULT > => 30
    rule Gsha3word < DEFAULT > => 6

    rule Gsload       < DEFAULT > => 50
    rule Gsstoreset   < DEFAULT > => 20000
    rule Gsstorereset < DEFAULT > => 5000
    rule Rsstoreclear < DEFAULT > => 15000

    rule Glog      < DEFAULT > => 375
    rule Glogdata  < DEFAULT > => 8
    rule Glogtopic < DEFAULT > => 375

    rule Gcall        < DEFAULT > => 40
    rule Gcallstipend < DEFAULT > => 2300
    rule Gcallvalue   < DEFAULT > => 9000
    rule Gnewaccount  < DEFAULT > => 25000

    rule Gcreate       < DEFAULT > => 32000
    rule Gcodedeposit  < DEFAULT > => 200
    rule Gselfdestruct < DEFAULT > => 0
    rule Rselfdestruct < DEFAULT > => 24000

    rule Gmemory    < DEFAULT > => 3
    rule Gquadcoeff < DEFAULT > => 512
    rule Gcopy      < DEFAULT > => 3

    rule Gtransaction   < DEFAULT > => 21000
    rule Gtxcreate      < DEFAULT > => 53000
    rule Gtxdatazero    < DEFAULT > => 4
    rule Gtxdatanonzero < DEFAULT > => 68

    rule Gjumpdest    < DEFAULT > => 1
    rule Gbalance     < DEFAULT > => 20
    rule Gblockhash   < DEFAULT > => 20
    rule Gextcodesize < DEFAULT > => 20
    rule Gextcodecopy < DEFAULT > => 20

    rule Gselfdestructnewaccount << DEFAULT >> => false
    rule Gstaticcalldepth        << DEFAULT >> => true
```

```c++
struct EVMSchedule
{
    EVMSchedule(): tierStepGas(std::array<unsigned, 8>{{0, 2, 3, 5, 8, 10, 20, 0}}) {}
    EVMSchedule(bool _efcd, bool _hdc, unsigned const& _txCreateGas): exceptionalFailedCodeDeposit(_efcd), haveDelegateCall(_hdc), tierStepGas(std::array<unsigned, 8>{{0, 2, 3, 5, 8, 10, 20, 0}}), txCreateGas(_txCreateGas) {}
    bool exceptionalFailedCodeDeposit = true;
    bool haveDelegateCall = true;
    bool eip150Mode = false;
    bool eip158Mode = false;
    bool haveRevert = false;
    bool haveReturnData = false;
    bool haveStaticCall = false;
    bool haveCreate2 = false;
    std::array<unsigned, 8> tierStepGas;

    unsigned expGas = 10;
    unsigned expByteGas = 10;
    unsigned sha3Gas = 30;
    unsigned sha3WordGas = 6;

    unsigned sloadGas = 50;
    unsigned sstoreSetGas = 20000;
    unsigned sstoreResetGas = 5000;
    unsigned sstoreRefundGas = 15000;

    unsigned logGas = 375;
    unsigned logDataGas = 8;
    unsigned logTopicGas = 375;

    unsigned callGas = 40;
    unsigned callStipend = 2300;
    unsigned callValueTransferGas = 9000;
    unsigned callNewAccountGas = 25000;

    unsigned createGas = 32000;
    unsigned createDataGas = 200;
    unsigned suicideGas = 0;
    unsigned suicideRefundGas = 24000;

    unsigned memoryGas = 3;
    unsigned quadCoeffDiv = 512;
    unsigned copyGas = 3;

    unsigned txGas = 21000;
    unsigned txCreateGas = 53000;
    unsigned txDataZeroGas = 4;
    unsigned txDataNonZeroGas = 68;

    unsigned jumpdestGas = 1;
    unsigned balanceGas = 20;
    unsigned blockhashGas = 20;
    unsigned extcodesizeGas = 20;
    unsigned extcodecopyGas = 20;

    unsigned maxCodeSize = unsigned(-1);

    bool staticCallDepthLimit() const { return !eip150Mode; }
    bool suicideNewAccountGas() const { return !eip150Mode; }
    bool suicideChargesNewAccountGas() const { return eip150Mode; }
    bool emptinessIsNonexistence() const { return eip158Mode; }
    bool zeroValueTransferChargesNewAccountGas() const { return !eip158Mode; }
};
```

### Frontier Schedule

```{.k .uiuck .rvk}
    syntax Schedule ::= "FRONTIER"
 // ------------------------------
    rule Gtxcreate  < FRONTIER > => 21000
    rule SCHEDCONST < FRONTIER > => SCHEDCONST < DEFAULT > requires SCHEDCONST =/=K Gtxcreate

    rule SCHEDFLAG << FRONTIER >> => SCHEDFLAG << DEFAULT >>
```

```c++
static const EVMSchedule FrontierSchedule = EVMSchedule(false, false, 21000);
```

### Homestead Schedule

```{.k .uiuck .rvk}
    syntax Schedule ::= "HOMESTEAD"
 // -------------------------------
    rule SCHEDCONST < HOMESTEAD > => SCHEDCONST < DEFAULT >

    rule SCHEDFLAG << HOMESTEAD >> => SCHEDFLAG << DEFAULT >>
```

```c++
static const EVMSchedule HomesteadSchedule = EVMSchedule(true, true, 53000);
```

### EIP150 Schedule

```{.k .uiuck .rvk}
    syntax Schedule ::= "EIP150"
 // ----------------------------
    rule Gbalance      < EIP150 > => 400
    rule Gsload        < EIP150 > => 200
    rule Gcall         < EIP150 > => 700
    rule Gselfdestruct < EIP150 > => 5000
    rule Gextcodesize  < EIP150 > => 700
    rule Gextcodecopy  < EIP150 > => 700
    rule SCHEDCONST    < EIP150 > => SCHEDCONST < HOMESTEAD >
      requires notBool      ( SCHEDCONST ==K Gbalance      orBool SCHEDCONST ==K Gsload       orBool SCHEDCONST ==K Gcall
                       orBool SCHEDCONST ==K Gselfdestruct orBool SCHEDCONST ==K Gextcodesize orBool SCHEDCONST ==K Gextcodecopy
                            )

    rule Gselfdestructnewaccount << EIP150 >> => true
    rule Gstaticcalldepth        << EIP150 >> => false
```

```c++
static const EVMSchedule EIP150Schedule = []
{
    EVMSchedule schedule = HomesteadSchedule;
    schedule.eip150Mode = true;
    schedule.extcodesizeGas = 700;
    schedule.extcodecopyGas = 700;
    schedule.balanceGas = 400;
    schedule.sloadGas = 200;
    schedule.callGas = 700;
    schedule.suicideGas = 5000;
    schedule.maxCodeSize = 0x6000;
    return schedule;
}();
```

### EIP158 Schedule

```{.k .uiuck .rvk}
    syntax Schedule ::= "EIP158"
 // ----------------------------
    rule Gexpbyte   < EIP158 > => 50
    rule SCHEDCONST < EIP158 > => SCHEDCONST < EIP150 > requires SCHEDCONST =/=K Gexpbyte

    rule SCHEDFLAG << EIP158 >> => SCHEDFLAG << EIP150 >>
```

```c++
static const EVMSchedule EIP158Schedule = []
{
    EVMSchedule schedule = EIP150Schedule;
    schedule.expByteGas = 50;
    schedule.eip158Mode = true;
    return schedule;
}();
```

### Metropolis Schedule

```{.k .uiuck .rvk}
    syntax Schedule ::= "METROPOLIS"
 // --------------------------------
    rule Gblockhash < METROPOLIS > => 800
    rule SCHEDCONST < METROPOLIS > => SCHEDCONST < EIP158 >
      requires SCHEDCONST =/=K Gblockhash

    rule SCHEDFLAG << METROPOLIS >> => SCHEDFLAG << EIP158 >>
```

```c++
static const EVMSchedule MetropolisSchedule = []
{
    EVMSchedule schedule = EIP158Schedule;
    schedule.blockhashGas = 800;
    schedule.haveRevert = true;
    schedule.haveReturnData = true;
    schedule.haveStaticCall = true;
    schedule.haveCreate2 = true;
    return schedule;
}();
```

EVM Program Representations
===========================

EVM programs are represented algebraically in K, but programs can load and manipulate program data directly.
The opcodes `CODECOPY` and `EXTCODECOPY` rely on the assembled form of the programs being present.
The opcode `CREATE` relies on being able to interperet EVM data as a program.

This is a program representation dependence, which we might want to avoid.
Perhaps the only program representation dependence we should have is the hash of the program; doing so achieves:

-   Program representation independence (different analysis tools on the language don't have to ensure they have a common representation of programs, just a common interperetation of the data-files holding programs).
-   Programming language independence (we wouldn't even have to commit to a particular language or interperetation of the data-file).
-   Only depending on the hash allows us to know that we have *exactly* the correct data-file (program), and nothing more.

Disassembler
------------

After interpreting the strings representing programs as a `WordStack`, it should be changed into an `OpCodes` for use by the EVM semantics.

-   `#dasmOpCodes` interperets `WordStack` as an `OpCodes`.
-   `#dasmPUSH` handles the case of a `PushOp`.
-   `#dasmOpCode` interperets a `Int` as an `OpCode`.

```{.k .uiuck .rvk}
    syntax OpCodes ::= #dasmOpCodes ( WordStack ) [function]
 // --------------------------------------------------------
    rule #dasmOpCodes( .WordStack ) => .OpCodes
    rule #dasmOpCodes( W : WS )     => #dasmOpCode(W)   ; #dasmOpCodes(WS) requires W >=Int 0   andBool W <=Int 95
    rule #dasmOpCodes( W : WS )     => #dasmOpCode(W)   ; #dasmOpCodes(WS) requires W >=Int 165 andBool W <=Int 255
    rule #dasmOpCodes( W : WS )     => DUP(W -Int 127)  ; #dasmOpCodes(WS) requires W >=Int 128 andBool W <=Int 143
    rule #dasmOpCodes( W : WS )     => SWAP(W -Int 143) ; #dasmOpCodes(WS) requires W >=Int 144 andBool W <=Int 159
    rule #dasmOpCodes( W : WS )     => LOG(W -Int 160)  ; #dasmOpCodes(WS) requires W >=Int 160 andBool W <=Int 164
    rule #dasmOpCodes( W : WS )     => #dasmPUSH( W -Int 95 , WS )         requires W >=Int 96  andBool W <=Int 127

    syntax OpCodes ::= #dasmPUSH ( Int , WordStack ) [function]
 // -----------------------------------------------------------
    rule #dasmPUSH( W , WS ) => PUSH(W, #asWord(#take(W, WS))) ; #dasmOpCodes(#drop(W, WS))

    syntax OpCode ::= #dasmOpCode ( Int ) [function]
 // ------------------------------------------------
    rule #dasmOpCode(   0 ) => STOP
    rule #dasmOpCode(   1 ) => ADD
    rule #dasmOpCode(   2 ) => MUL
    rule #dasmOpCode(   3 ) => SUB
    rule #dasmOpCode(   4 ) => DIV
    rule #dasmOpCode(   5 ) => SDIV
    rule #dasmOpCode(   6 ) => MOD
    rule #dasmOpCode(   7 ) => SMOD
    rule #dasmOpCode(   8 ) => ADDMOD
    rule #dasmOpCode(   9 ) => MULMOD
    rule #dasmOpCode(  10 ) => EXP
    rule #dasmOpCode(  11 ) => SIGNEXTEND
    rule #dasmOpCode(  16 ) => LT
    rule #dasmOpCode(  17 ) => GT
    rule #dasmOpCode(  18 ) => SLT
    rule #dasmOpCode(  19 ) => SGT
    rule #dasmOpCode(  20 ) => EQ
    rule #dasmOpCode(  21 ) => ISZERO
    rule #dasmOpCode(  22 ) => AND
    rule #dasmOpCode(  23 ) => EVMOR
    rule #dasmOpCode(  24 ) => XOR
    rule #dasmOpCode(  25 ) => NOT
    rule #dasmOpCode(  26 ) => BYTE
    rule #dasmOpCode(  32 ) => SHA3
    rule #dasmOpCode(  48 ) => ADDRESS
    rule #dasmOpCode(  49 ) => BALANCE
    rule #dasmOpCode(  50 ) => ORIGIN
    rule #dasmOpCode(  51 ) => CALLER
    rule #dasmOpCode(  52 ) => CALLVALUE
    rule #dasmOpCode(  53 ) => CALLDATALOAD
    rule #dasmOpCode(  54 ) => CALLDATASIZE
    rule #dasmOpCode(  55 ) => CALLDATACOPY
    rule #dasmOpCode(  56 ) => CODESIZE
    rule #dasmOpCode(  57 ) => CODECOPY
    rule #dasmOpCode(  58 ) => GASPRICE
    rule #dasmOpCode(  59 ) => EXTCODESIZE
    rule #dasmOpCode(  60 ) => EXTCODECOPY
    rule #dasmOpCode(  64 ) => BLOCKHASH
    rule #dasmOpCode(  65 ) => COINBASE
    rule #dasmOpCode(  66 ) => TIMESTAMP
    rule #dasmOpCode(  67 ) => NUMBER
    rule #dasmOpCode(  68 ) => DIFFICULTY
    rule #dasmOpCode(  69 ) => GASLIMIT
    rule #dasmOpCode(  80 ) => POP
    rule #dasmOpCode(  81 ) => MLOAD
    rule #dasmOpCode(  82 ) => MSTORE
    rule #dasmOpCode(  83 ) => MSTORE8
    rule #dasmOpCode(  84 ) => SLOAD
    rule #dasmOpCode(  85 ) => SSTORE
    rule #dasmOpCode(  86 ) => JUMP
    rule #dasmOpCode(  87 ) => JUMPI
    rule #dasmOpCode(  88 ) => PC
    rule #dasmOpCode(  89 ) => MSIZE
    rule #dasmOpCode(  90 ) => GAS
    rule #dasmOpCode(  91 ) => JUMPDEST
    rule #dasmOpCode( 240 ) => CREATE
    rule #dasmOpCode( 241 ) => CALL
    rule #dasmOpCode( 242 ) => CALLCODE
    rule #dasmOpCode( 243 ) => RETURN
    rule #dasmOpCode( 244 ) => DELEGATECALL
    rule #dasmOpCode( 255 ) => SELFDESTRUCT
    rule #dasmOpCode(   W ) => INVALID(W) [owise]
```

Assembler
---------

-   `#asmOpCodes` gives the `WordStack` representation of an `OpCodes`.

```{.k .uiuck .rvk}
    syntax WordStack ::= #asmOpCodes ( OpCodes ) [function]
 // -------------------------------------------------------
    rule #asmOpCodes( .OpCodes )           => .WordStack
    rule #asmOpCodes( STOP         ; OPS ) =>   0 : #asmOpCodes(OPS)
    rule #asmOpCodes( ADD          ; OPS ) =>   1 : #asmOpCodes(OPS)
    rule #asmOpCodes( MUL          ; OPS ) =>   2 : #asmOpCodes(OPS)
    rule #asmOpCodes( SUB          ; OPS ) =>   3 : #asmOpCodes(OPS)
    rule #asmOpCodes( DIV          ; OPS ) =>   4 : #asmOpCodes(OPS)
    rule #asmOpCodes( SDIV         ; OPS ) =>   5 : #asmOpCodes(OPS)
    rule #asmOpCodes( MOD          ; OPS ) =>   6 : #asmOpCodes(OPS)
    rule #asmOpCodes( SMOD         ; OPS ) =>   7 : #asmOpCodes(OPS)
    rule #asmOpCodes( ADDMOD       ; OPS ) =>   8 : #asmOpCodes(OPS)
    rule #asmOpCodes( MULMOD       ; OPS ) =>   9 : #asmOpCodes(OPS)
    rule #asmOpCodes( EXP          ; OPS ) =>  10 : #asmOpCodes(OPS)
    rule #asmOpCodes( SIGNEXTEND   ; OPS ) =>  11 : #asmOpCodes(OPS)
    rule #asmOpCodes( LT           ; OPS ) =>  16 : #asmOpCodes(OPS)
    rule #asmOpCodes( GT           ; OPS ) =>  17 : #asmOpCodes(OPS)
    rule #asmOpCodes( SLT          ; OPS ) =>  18 : #asmOpCodes(OPS)
    rule #asmOpCodes( SGT          ; OPS ) =>  19 : #asmOpCodes(OPS)
    rule #asmOpCodes( EQ           ; OPS ) =>  20 : #asmOpCodes(OPS)
    rule #asmOpCodes( ISZERO       ; OPS ) =>  21 : #asmOpCodes(OPS)
    rule #asmOpCodes( AND          ; OPS ) =>  22 : #asmOpCodes(OPS)
    rule #asmOpCodes( EVMOR        ; OPS ) =>  23 : #asmOpCodes(OPS)
    rule #asmOpCodes( XOR          ; OPS ) =>  24 : #asmOpCodes(OPS)
    rule #asmOpCodes( NOT          ; OPS ) =>  25 : #asmOpCodes(OPS)
    rule #asmOpCodes( BYTE         ; OPS ) =>  26 : #asmOpCodes(OPS)
    rule #asmOpCodes( SHA3         ; OPS ) =>  32 : #asmOpCodes(OPS)
    rule #asmOpCodes( ADDRESS      ; OPS ) =>  48 : #asmOpCodes(OPS)
    rule #asmOpCodes( BALANCE      ; OPS ) =>  49 : #asmOpCodes(OPS)
    rule #asmOpCodes( ORIGIN       ; OPS ) =>  50 : #asmOpCodes(OPS)
    rule #asmOpCodes( CALLER       ; OPS ) =>  51 : #asmOpCodes(OPS)
    rule #asmOpCodes( CALLVALUE    ; OPS ) =>  52 : #asmOpCodes(OPS)
    rule #asmOpCodes( CALLDATALOAD ; OPS ) =>  53 : #asmOpCodes(OPS)
    rule #asmOpCodes( CALLDATASIZE ; OPS ) =>  54 : #asmOpCodes(OPS)
    rule #asmOpCodes( CALLDATACOPY ; OPS ) =>  55 : #asmOpCodes(OPS)
    rule #asmOpCodes( CODESIZE     ; OPS ) =>  56 : #asmOpCodes(OPS)
    rule #asmOpCodes( CODECOPY     ; OPS ) =>  57 : #asmOpCodes(OPS)
    rule #asmOpCodes( GASPRICE     ; OPS ) =>  58 : #asmOpCodes(OPS)
    rule #asmOpCodes( EXTCODESIZE  ; OPS ) =>  59 : #asmOpCodes(OPS)
    rule #asmOpCodes( EXTCODECOPY  ; OPS ) =>  60 : #asmOpCodes(OPS)
    rule #asmOpCodes( BLOCKHASH    ; OPS ) =>  64 : #asmOpCodes(OPS)
    rule #asmOpCodes( COINBASE     ; OPS ) =>  65 : #asmOpCodes(OPS)
    rule #asmOpCodes( TIMESTAMP    ; OPS ) =>  66 : #asmOpCodes(OPS)
    rule #asmOpCodes( NUMBER       ; OPS ) =>  67 : #asmOpCodes(OPS)
    rule #asmOpCodes( DIFFICULTY   ; OPS ) =>  68 : #asmOpCodes(OPS)
    rule #asmOpCodes( GASLIMIT     ; OPS ) =>  69 : #asmOpCodes(OPS)
    rule #asmOpCodes( POP          ; OPS ) =>  80 : #asmOpCodes(OPS)
    rule #asmOpCodes( MLOAD        ; OPS ) =>  81 : #asmOpCodes(OPS)
    rule #asmOpCodes( MSTORE       ; OPS ) =>  82 : #asmOpCodes(OPS)
    rule #asmOpCodes( MSTORE8      ; OPS ) =>  83 : #asmOpCodes(OPS)
    rule #asmOpCodes( SLOAD        ; OPS ) =>  84 : #asmOpCodes(OPS)
    rule #asmOpCodes( SSTORE       ; OPS ) =>  85 : #asmOpCodes(OPS)
    rule #asmOpCodes( JUMP         ; OPS ) =>  86 : #asmOpCodes(OPS)
    rule #asmOpCodes( JUMPI        ; OPS ) =>  87 : #asmOpCodes(OPS)
    rule #asmOpCodes( PC           ; OPS ) =>  88 : #asmOpCodes(OPS)
    rule #asmOpCodes( MSIZE        ; OPS ) =>  89 : #asmOpCodes(OPS)
    rule #asmOpCodes( GAS          ; OPS ) =>  90 : #asmOpCodes(OPS)
    rule #asmOpCodes( JUMPDEST     ; OPS ) =>  91 : #asmOpCodes(OPS)
    rule #asmOpCodes( CREATE       ; OPS ) => 240 : #asmOpCodes(OPS)
    rule #asmOpCodes( CALL         ; OPS ) => 241 : #asmOpCodes(OPS)
    rule #asmOpCodes( CALLCODE     ; OPS ) => 242 : #asmOpCodes(OPS)
    rule #asmOpCodes( RETURN       ; OPS ) => 243 : #asmOpCodes(OPS)
    rule #asmOpCodes( DELEGATECALL ; OPS ) => 244 : #asmOpCodes(OPS)
    rule #asmOpCodes( INVALID(W)   ; OPS ) => W   : #asmOpCodes(OPS)
    rule #asmOpCodes( SELFDESTRUCT ; OPS ) => 255 : #asmOpCodes(OPS)
    rule #asmOpCodes( DUP(W)       ; OPS ) => W +Int 127 : #asmOpCodes(OPS)
    rule #asmOpCodes( SWAP(W)      ; OPS ) => W +Int 143 : #asmOpCodes(OPS)
    rule #asmOpCodes( LOG(W)       ; OPS ) => W +Int 160 : #asmOpCodes(OPS)
    rule #asmOpCodes( PUSH(N, W)   ; OPS ) => N +Int 95  : (#padToWidth(N, #asByteStack(W)) ++ #asmOpCodes(OPS))
endmodule
```
