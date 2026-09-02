#ifndef MATCH_DIALECT
#define MATCH_DIALECT

include "mlir/IR/OpBase.td"

// dialect definition
def Match_Dialect : Dialect{
    let name = "match";
    let summary = "A dialect for the optimisation of functional pattern matching in MLIR";
    let description = [{
        The match dialect is a dialect for the representation and optimisation of functional pattern matching
        constructs in MLIR. It provides a set of operations and types to enable this, and in particular enables
        the application of maranget's algorithm onto these language constructs.
    }];
    let cppNamespace = "::mlir::match";
}

// We specify the BASE class for all standalone operations
class Match_Op<string mnemonic, list<Trait> traits = []> :
        Op<Match_Dialect, mnemonic, traits>;

#endif // MATCH_DIALECT