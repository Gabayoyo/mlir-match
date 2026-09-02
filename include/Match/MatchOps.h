#ifndef MATCH_MATCHOPS_H
#define MATCH_MATCHOPS_H

#include "Match/MatchDialect.h"

// we bring in the standard IR/parse support
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpImplementation.h"

// we also bring in anything that we use in the tablegen
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"

// generated class decls for MatchOp
#define GET_OP_CLASSES
#include "Match/MatchOps.h.inc"

#endif // MATCH_MATCHOPS_H