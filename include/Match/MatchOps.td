#ifndef MATCH_OPS
#define MATCH_OPS

include "MatchDialect.td"
include "MatchAttrs.td"
include "mlir/Interfaces/InferTypeOpInterface.td"
include "mlir/Interfaces/SideEffectInterfaces.td"
include "mlir/Interfaces/ControlFlowInterfaces.td"


// Body terminator - yields the arm's results when that arm is selected.
// Defined above Match_MatchOp since it relies on it
def Match_YieldOp : Match_Op<"yield", [
    Terminator,
    HasParent<"MatchOp">,
    // Needed as terminator returns to parent match op
    RegionBranchTerminatorOpInterface
]> {
  let arguments = (ins Variadic<AnyType>:$results);
  let assemblyFormat = "attr-dict ($results^ `:` type($results))?";
}

// core match operation
def Match_MatchOp : Match_Op<"match", [
    RecursiveMemoryEffects,
    RegionBranchOpInterface,
    // so that the terminator is always a match.yield op
    SingleBlockImplicitTerminator<"match::YieldOp">,
]> {
    // The match operation takes a scrutinee, and returns the results of the selected arm.
    // Also takes an optional list of patterns, one per arm, which are used to determine which arm is selected.
    let arguments = (ins AnyType:$scrutinee,
                         OptionalAttr<Match_PatternList>:$patterns);
    let results = (outs Variadic<AnyType>:$results);
    // region 0 is the default, 1..N is the arms
    let regions = (region AnyRegion:$otherwise,
                            VariadicRegion<AnyRegion>:$arms);
    let hasVerifier = 1;
    // case/default keywords around regions need a hand-written parse/print.
    let hasCustomAssemblyFormat = 1;

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
    let assemblyFormat = "attr-dict $condition";
}

def Match_DeconstructOp : Match_Op<"deconstruct", [
    Pure, // pure means no side effects, can be duplicated or eliminated if unused
]> {
    let arguments = (ins AnyType:$value, StrAttr:$constructor);
    let results = (outs I1:$matched, Variadic<AnyType>:$fields);
    let hasVerifier = 1;
    let hasCustomAssemblyFormat = 1;
}

#endif // MATCH_OPS
