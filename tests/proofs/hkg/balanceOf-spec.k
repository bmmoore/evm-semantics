// The Hacker Gold (HKG) Token Smart Contract
// ==========================================

// BalanceOf Function
// ------------------

// Here we provide a specification file containing a reachability rule for the
// verifying the correctness of the HKG Token's BalanceOf Function.


module BALANCE-OF-SPEC
    imports ETHEREUM-SIMULATION
    // The First Rule Uses Desugaring to put the correct arguments in the Call Data Cell
    rule <k>            #execute ... </k>
         <exit-code>    1            </exit-code>
         <mode>         NORMAL       </mode>
         <schedule>     DEFAULT      </schedule>

         <output>        .WordStack </output>
         <memoryUsed>    4          </memoryUsed>
         <callDepth>     0          </callDepth>
         <callStack>     .List      </callStack>
         <interimStates> .List      </interimStates>
         <callLog>       .Set       </callLog>

         <program>      %HKG_Program </program>
         <id>           %ACCT_ID     </id>
         <caller>       %CALLER_ID   </caller>
         <callData>
                    #abiCallData("balanceOf", #address(T), .TypedArgs)
                    =>
                    #parseHexBytes("70a08231") ++ #uint(T)
         </callData>
         <callValue>    0            </callValue>

         <wordStack>    .WordStack    => _      </wordStack>
         <localMem>     .Map          => ?B:Map </localMem>
         <pc>           0                       </pc>
         <gas>          1000  => _              </gas>
         <previousGas>  _     => _              </previousGas>

         <selfDestruct> .Set    </selfDestruct>
         <log>          .Set    </log>
         <refund>       0  => _ </refund>

         <gasPrice>     _               </gasPrice>
         <origin>       %ORIGIN_ID      </origin>
         <gasLimit>     _               </gasLimit>
         <coinbase>     %COINBASE_VALUE </coinbase>
         <timestamp>    1               </timestamp>
         <number>       0               </number>
         <previousHash> 0               </previousHash>
         <difficulty>   256             </difficulty>

         <activeAccounts> SetItem ( %ACCT_ID ) </activeAccounts>
         <accounts>
           <account>
             <acctID>  %ACCT_ID      </acctID>
             <balance> BAL           </balance>
             <code>    %HKG_Program  </code>
             <acctMap> "nonce" |-> 0 </acctMap>
             <storage> _
             </storage>
           </account>
         </accounts>

        requires #sizeWordStack(WS) <Int 1018
            andBool 0 <=Int T andBool T <Int 1461501637330902918203684832716283019655932542976


    rule <k> #execute ... </k>
         <exit-code> 1       </exit-code>
         <mode>      NORMAL  </mode>
         <schedule>  DEFAULT </schedule>

         <output>        .WordStack </output>
         <memoryUsed>    4          </memoryUsed>
         <callDepth>     0          </callDepth>
         <callStack>     .List      </callStack>
         <interimStates> .List      </interimStates>
         <callLog>       .Set       </callLog>

         <program>      %HKG_Program </program>
         <id>           %ACCT_ID     </id>
         <caller>       %CALLER_ID   </caller>
         <callData>     #parseHexBytes("70a08231") ++ #uint(T) </callData>
         // "70a08231": "balanceOf(address)"
         <callValue>    0            </callValue>

//         <wordStack>    .WordStack    => _ : 360 : 1889567281 : .WordStack </wordStack>
         <wordStack>    .WordStack    => _    </wordStack>
         <localMem>     .Map  => ?B:Map       </localMem>
         <pc>           0     => 358          </pc>
         <gas>          1000  => _            </gas>
         <previousGas>  _     => _            </previousGas>

         <selfDestruct> .Set    </selfDestruct>
         <log>          .Set    </log>
         <refund>       0  => _ </refund>

         <gasPrice>     _               </gasPrice>
         <origin>       %ORIGIN_ID      </origin>
         <gasLimit>     _               </gasLimit>
         <coinbase>     %COINBASE_VALUE </coinbase>
         <timestamp>    1               </timestamp>
         <number>       0               </number>
         <previousHash> 0               </previousHash>
         <difficulty>   256             </difficulty>

         <activeAccounts> SetItem ( %ACCT_ID ) </activeAccounts>
         <accounts>
           <account>
             <acctID>  %ACCT_ID      </acctID>
             <balance> BAL           </balance>
             <code>    %HKG_Program  </code>
             <acctMap> "nonce" |-> 0 </acctMap>
             <storage> _
             </storage>
           </account>
         </accounts>

      requires #sizeWordStack(WS) <Int 1018
          andBool 0 <=Int T andBool T <Int 1461501637330902918203684832716283019655932542976

endmodule

