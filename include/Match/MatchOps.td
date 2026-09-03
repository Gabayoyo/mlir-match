#ifndef MATCH_OPS
#define MATCH_OPS

include "MatchDialect.td"
include "mlir/Interfaces/InferTypeOpInterface.td"
include "mlir/Interfaces/SideEffectInterfaces.td"
include "mlir/Interfaces/ControlFlowInterfaces.td"


// Body terminator - yields the arm's results when that arm is selected.
// Defined above Match_MatchOp since it relies on it; the mnemonic is bare
// ("yield") because Match_Op already prefixes the dialect name.
def Match_YieldOp : Match_Op<"yield", [
    Terminator,
    HasParent<"MatchOp">,
    RegionBranchTerminatorOpInterface // Needed as terminator returns to parent match op
]> {
  let arguments = (ins Variadic<AnyType>:$results);
}

// core match operation
def Match_MatchOp : Match_Op<"match", [
    RecursiveMemoryEffects,
    RegionBranchOpInterface,
    SingleBlockImplicitTerminator<"match::YieldOp">, // terminator is always a match.yield op
]> {
    // The match operation takes a scrutinee, and returns the results of the selected arm.
    let arguments = (ins AnyType:$scrutinee);
    let results = (outs Variadic<AnyType>:$results);
    // region 0 is the default, 1..N is the arms
    let regions = (region AnyRegion:$otherwise,
                            VariadicRegion<AnyRegion>:$arms);
    let hasVerifier = 1;

    // RegionBranchOpInterface has no default for getSuccessorRegions
    // so we use extraClassDeclaration here to add the getSuccessorRegions method
    // to the generated MatchOp class, which is required by the RegionBranchOpInterface
    // (has to be added manually in this way)
    let extraClassDeclaration = [{
        using ::mlir::RegionBranchOpInterface::Trait<MatchOp>::getSuccessorRegions;
        void getSuccessorRegions(
            ::mlir::RegionBranchPoint point,
            ::llvm::SmallVectorImpl<::mlir::RegionSuccessor> &regions);
        ::mlir::ValueRange getSuccessorInputs(::mlir::RegionSuccessor successor);
    }];
}

// guard marker op - separates the guard computation from the body within an arm
def Match_GuardOp : Match_Op<"guard", [
    Pure, // pure means no side effects, can be duplicated or eliminated if unused
    HasParent<"MatchOp">,
]> {
    let arguments = (ins I1:$condition);
}

#endif // MATCH_OPS
