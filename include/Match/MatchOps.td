#ifndef MATCH_OPS
#define MATCH_OPS

include "MatchDialect.td"
include "mlir/Interfaces/InferTypeOpInterface.td"
include "mlir/Interfaces/SideEffectInterfaces.td"
include "mlir/Interfaces/ControlFlowInterfaces.td"


// core match operation, which takes a scrutinee and a set of arms (each with a condition and body region)
def Match_MatchOp : Match_Op<"match", [
    RecursiveMemoryEffects,
    RegionBranchOpInterface
]> {
    let arguments = (ins AnyType:$scrutinee);
    let results = (outs Variadic<AnyType>:$results);

    // one arm per region, tried in order
    // each arm region holds exactly two blocks: 
    // - an entry condition block (terminated by match.cond_yield)
    // - body block (terminated by match.yield)
    let regions = (region VariadicRegion<AnyRegion>:$arms);

    let hasVerifier = 1;  // two blocks per arm, terminator checks, etc.

    // getSuccessorRegions has no default impl, so we must provide it
    // .td extraClassDeclaration is the only way to add that member to the generated op
    let extraClassDeclaration = [{
    // bring back the base's default getSuccessorRegions so that it isnt hidden by our override
    using ::mlir::RegionBranchOpInterface::Trait<MatchOp>::getSuccessorRegions;
    void getSuccessorRegions(
        ::mlir::RegionBranchPoint point,
        ::llvm::SmallVectorImpl<::mlir::RegionSuccessor> &regions);
}];
}

// Body terminator - yields the arm's results when that arm is selected.
def Match_YieldOp : Match_Op<"match.yield", [
    Terminator,
    HasParent<"MatchOp">,
    RegionBranchTerminatorOpInterface // Needed as terminator returns to parent match op
]> {
  let arguments = (ins Variadic<AnyType>:$results);
}

// Condition terminator - ends an arm's condition block
def Match_CondYieldOp : Match_Op<"match.cond_yield", [
    Terminator,
    HasParent<"MatchOp">,
    RegionBranchTerminatorOpInterface // Needed as terminator branches to other conditions
]> {
  let arguments = (ins I1:$matched); // yields I1 since its a bool
}

#endif // MATCH_OPS
