#include "Match/Conversion/MatchToSCF/Passes.h"
#include "Match/Conversion/LoweringUtils.h"
#include "Match/MatchOps.h"
#include "Match/MatchAttrs.h"
#include "Match/MatchTypes.h"

#include "llvm/ADT/STLExtras.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"

#include <optional>

namespace mlir {
namespace match {
namespace {

#define GEN_PASS_DEF_MATCHTOSCFPASS
#include "Match/Conversion/MatchToSCF/Passes.h.inc"

Value compilePattern(PatternAttr pattern, Value value, OpBuilder &builder,
                     SmallVectorImpl<Value> &bindings) {
  switch (getPatternKind(pattern)) {
    case PatternKind::Bind:
      // The value is captured, and the test always succeeds.
      bindings.push_back(value);
      return arith::ConstantOp::create(builder, value.getLoc(),
                                      builder.getBoolAttr(true));
    case PatternKind::Wildcard:
      // Nothing is captured, and the test always succeeds.
      return arith::ConstantOp::create(builder, value.getLoc(),
                                      builder.getBoolAttr(true));
    case PatternKind::Literal: {
      // The value must equal the payload.
      IntegerAttr payload = pattern.getPayload();
      Value literalValue =
          arith::ConstantOp::create(builder, value.getLoc(), payload);
      return arith::CmpIOp::create(builder, value.getLoc(),
                                  arith::CmpIPredicate::eq, value, literalValue);
    }
    case PatternKind::Constructor:
      break;
    }
  {
    // A constructor pattern deconstructs the value; its sub-patterns fold into
    // the deconstruct's match flag.
    auto constructor = lookupConstructor(value.getType(), pattern.getKind());

    if (!constructor)
      llvm_unreachable(
          "validated pattern kind is not a constructor of the value's type");

    // Result types are {i1, field types...}.
    SmallVector<Type> resultTypes;
    resultTypes.push_back(builder.getI1Type());
    resultTypes.append(constructor->fieldTypes.begin(),
                       constructor->fieldTypes.end());

    auto deconstructOp = match::DeconstructOp::create(
        builder, value.getLoc(), resultTypes, value, pattern.getKind());
    Value cond = deconstructOp.getResult(0); // the %matched flag

    for (auto [subpattern, fieldValue] :
         llvm::zip(pattern.getSubpatterns(),
                   deconstructOp.getResults().drop_front())) {
      cond = arith::AndIOp::create(
          builder, value.getLoc(), cond,
          compilePattern(subpattern, fieldValue, builder, bindings));
    }

    return cond;
  }
}

// The result values of a lowered chain, or nullopt when the chain terminated
// the current block itself (a guard-less arm or the default body).
using ChainResult = std::optional<SmallVector<Value>>;

// Lowers arms[armIndex..] plus the default into nested scf.if chains at
// `builder`'s insertion point, returning the values the chain produces.
ChainResult buildChain(MatchOp matchOp, unsigned armIndex,
                       Region &defaultRegion, OpBuilder &builder) {

  // We still have arms to process.
  if (armIndex < matchOp.getArms().size()) {
    Block &condDst = *builder.getInsertionBlock();
    Block &condSrc = matchOp.getArms()[armIndex].front();

    // Pattern for this arm, if the match carries one.
    auto patterns = matchOp.getPatterns();
    PatternAttr armPattern;
    if (patterns && !patterns->empty())
      armPattern = cast<PatternAttr>((*patterns)[armIndex]);
    bool hasPattern = static_cast<bool>(armPattern);

    // Split the arm at its guard: the ops before it compute the condition,
    // the ops after it form the body. Without a guard every op is body.
    GuardOp guardOp;
    bool beforeGuard = true;
    SmallVector<Operation *> condOps;
    for (Operation &op : llvm::make_early_inc_range(condSrc)) {
      if (auto guard = dyn_cast<GuardOp>(op)) {
        guardOp = guard;
        beforeGuard = false;
        continue;
      }
      if (beforeGuard)
        condOps.push_back(&op);
    }

    // An arm is terminal when it has no guard and its pattern (if any)
    // matches unconditionally - i.e. a "bind" or "wildcard" pattern
    bool unconditional = !guardOp && (!hasPattern || isIrrefutable(armPattern));

    if (unconditional) {
      SmallVector<Value> bindings;
      // An unconditional bind arm binds the scrutinee itself, so the arm body
      // can use the scrutinee directly.
      if (armPattern && getPatternKind(armPattern) == PatternKind::Bind)
        bindings.push_back(matchOp.getScrutinee());
      emitBody(condSrc, condDst, builder, bindings);
      return std::nullopt;
    }

    // Materialise the condition. Pattern ops come first so the binding values
    // dominate any hoisted guard ops that use them.
    SmallVector<Value> bindings;
    Value condition;
    if (hasPattern) {
      condition =
          compilePattern(armPattern, matchOp.getScrutinee(), builder, bindings);
      for (auto [argument, binding] :
           llvm::zip(condSrc.getArguments(), bindings))
        argument.replaceAllUsesWith(binding);
    }

    if (guardOp) {
      // Hoist the condition computation into the current block so it
      // dominates the scf.if and the region contents that use it.
      for (Operation *op : condOps)
        op->moveBefore(&condDst, builder.getInsertionPoint());
      if (hasPattern)
        condition = arith::AndIOp::create(builder, matchOp.getLoc(), condition,
                                          guardOp.getCondition());
      else
        condition = guardOp.getCondition();
      guardOp->erase();
    }

    // scf.if creation
    auto scfIf = scf::IfOp::create(builder, matchOp.getLoc(),
                                   matchOp.getResultTypes(), condition,
                                   /*addThenBlock=*/true,
                                   /*addElseBlock=*/true);

    // The body fills the then region.
    Block &thenBlock = scfIf.getThenRegion().front();
    emitBody(condSrc, thenBlock, builder, bindings);

    // The rest of the match goes into the if's else region.
    builder.setInsertionPointToEnd(&scfIf.getElseRegion().front());
    ChainResult inner =
        buildChain(matchOp, armIndex + 1, defaultRegion, builder);
    if (inner) {
      builder.setInsertionPointToEnd(&scfIf.getElseRegion().front());
      scf::YieldOp::create(builder, matchOp.getLoc(), ValueRange(*inner));
    }
    // The chain's result values are the scf.if's results.
    SmallVector<Value> results;
    results.append(scfIf.getResults().begin(), scfIf.getResults().end());
    return results;
  }

  // Base case: no arms remain; run the default body in the current block.
  emitBody(defaultRegion.front(), *builder.getInsertionBlock(), builder);
  return std::nullopt;
}

// This pass converts the match dialect to the SCF dialect
struct MatchToSCFPass : impl::MatchToSCFPassBase<MatchToSCFPass> {
  void runOnOperation() override {
    auto func = getOperation();
    SmallVector<MatchOp> matchOps;
    func.walk([&](MatchOp matchOp) { matchOps.push_back(matchOp); });

    for (MatchOp matchOp : matchOps) {
      OpBuilder builder(matchOp.getOperation());

      // A first arm that always matches (no guard, no conditional pattern)
      // is inlined in place of the match, as is the default with no arms.
      Region &unconditional = !matchOp.getArms().empty()
                                  ? matchOp.getArms().front()
                                  : matchOp.getOtherwise();
      auto patterns = matchOp.getPatterns();
      PatternAttr firstPattern;
      if (patterns && !patterns->empty())
        firstPattern = cast<PatternAttr>((*patterns)[0]);
      bool unconditionalArm = matchOp.getArms().empty() ||
                              (!hasGuard(unconditional) &&
                               (!firstPattern || isIrrefutable(firstPattern)));
      if (unconditionalArm) {
        Block &dst = *builder.getInsertionBlock();
        auto yield = cast<YieldOp>(unconditional.front().getTerminator());

        // An inlined bind arm binds the scrutinee itself; rewriting the arm's
        // arguments first keeps its yield referencing live values.
        SmallVector<Value> bindings;
        if (firstPattern && getPatternKind(firstPattern) == PatternKind::Bind)
          bindings.push_back(matchOp.getScrutinee());
        for (auto [argument, binding] :
             llvm::zip(unconditional.front().getArguments(), bindings))
          argument.replaceAllUsesWith(binding);
        SmallVector<Value> results(yield.getOperands());

        for (Operation &op :
             llvm::make_early_inc_range(unconditional.front())) {
          if (&op == yield)
            continue;
          op.moveBefore(&dst, builder.getInsertionPoint());
        }
        matchOp.replaceAllUsesWith(results);
        matchOp.erase();
        continue;
      }

      ChainResult results =
          buildChain(matchOp, 0, matchOp.getOtherwise(), builder);
      if (results) {
        matchOp.replaceAllUsesWith(*results);
        matchOp.erase();
      }
    }
  }
};

} // namespace

std::unique_ptr<Pass> createMatchToSCFPass() {
  return std::make_unique<MatchToSCFPass>();
}

} // namespace match
} // namespace mlir
