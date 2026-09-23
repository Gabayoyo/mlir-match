#include "Match/Conversion/MatchToLLVM/Passes.h"
#include "Match/Conversion/MatchToLLVM/MatchToLLVM.h"
#include "Match/MatchOps.h"
#include "Match/MatchAttrs.h"
#include "Match/MatchTypes.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Transforms/DialectConversion.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Conversion/LLVMCommon/TypeConverter.h"
#include "mlir/Conversion/FuncToLLVM/ConvertFuncToLLVM.h"

#include <utility>

namespace mlir {

namespace match {

namespace {

#define GEN_PASS_DEF_MATCHTOLLVMPASS
#include "Match/Conversion/MatchToLLVM/Passes.h.inc"
#include <cmath>
#include <iterator>

// struct extends the OpConversionPattern class to provide a custom lowering for
// the DeconstructOp
struct DeconstructOpLowering : public OpConversionPattern<DeconstructOp> {
  using OpConversionPattern<DeconstructOp>::OpConversionPattern;

  LogicalResult
  matchAndRewrite(DeconstructOp op, OpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override;
};

LogicalResult DeconstructOpLowering::matchAndRewrite(
    DeconstructOp op, OpAdaptor adaptor,
    ConversionPatternRewriter &rewriter) const {
  Location loc = op.getLoc();
  Type srcType = op.getValue().getType();

  SmallVector<ConstructorDescriptor> constructors = getConstructors(srcType);
  if (constructors.empty())
    return rewriter.notifyMatchFailure(op, "type has no constructors");

  std::optional<ConstructorDescriptor> constructor =
      lookupConstructor(srcType, op.getConstructor());
  if (!constructor)
    return rewriter.notifyMatchFailure(op, "unknown constructor");

  // A type with more than one constructor keeps a tag in field 0, holding the
  // constructor's position in the table.
  bool tagged = constructors.size() > 1;
  int64_t tag = 0;
  for (unsigned i = 0; i < constructors.size(); ++i)
    if (constructors[i].name == op.getConstructor())
      tag = i;

  Value container = adaptor.getValue();
  SmallVector<Value> results;

  // result 0: the matched result
  if (tagged) {
    // We create an extractValueOp for the structs
    Value tagValue = LLVM::ExtractValueOp::create(rewriter, loc, container,
                                                  ArrayRef<int64_t>{0});
    Value expected = arith::ConstantOp::create(
        rewriter, loc, rewriter.getI32IntegerAttr(static_cast<int32_t>(tag)));
        
    results.push_back(arith::CmpIOp::create(
        rewriter, loc, arith::CmpIPredicate::eq, tagValue, expected));
  } else {
    results.push_back(
        arith::ConstantOp::create(rewriter, loc, rewriter.getBoolAttr(true)));
  }

  // One extract per field: each replaces a result the arms already use.
  for (unsigned i = 0; i < constructor->fieldTypes.size(); ++i) {
    int64_t slot = tagged ? 1 + i : i;
    results.push_back(LLVM::ExtractValueOp::create(rewriter, loc, container,
                                                   ArrayRef<int64_t>{slot}));
  }

  rewriter.replaceOp(op, results);
  return success();
}

struct MatchToLLVMPass : public impl::MatchToLLVMPassBase<MatchToLLVMPass> {
  void runOnOperation() override {
    LLVMTypeConverter converter(&getContext());
    configureMatchToLLVMTypeConverter(converter);

    RewritePatternSet patterns(&getContext());
    populateMatchToLLVMConversionPatterns(converter, patterns);

    // match-typed values enter through function signatures, so the func
    // dialect has to be converted alongside the match ops.
    populateFuncToLLVMConversionPatterns(converter, patterns);

    ConversionTarget target(getContext());
    configureMatchToLLVMConversionLegality(target);

    if (failed(applyPartialConversion(getOperation(), target,
                                      std::move(patterns)))) {
      signalPassFailure();
    }
  }
};

} // namespace

void configureMatchToLLVMTypeConverter(LLVMTypeConverter &converter) {
  MLIRContext *context = &converter.getContext();

  // `!match.option<T>`: a 32-bit tag field followed by the payload, with
  // `some` = 0 and `none` = 1.
  converter.addConversion(
      [context, &converter](OptionType type) -> std::optional<Type> {
        Type payload = converter.convertType(type.getPayload());
        if (!payload)
          return std::nullopt;
        return LLVM::LLVMStructType::getLiteral(
            context, {IntegerType::get(context, 32), payload});
      });

  // `!match.pair<T1, T2>`: a struct with the two fields.
  converter.addConversion(
      [context, &converter](PairType type) -> std::optional<Type> {
        Type first = converter.convertType(type.getFirst());
        Type second = converter.convertType(type.getSecond());
        if (!first || !second)
          return std::nullopt;
        return LLVM::LLVMStructType::getLiteral(context, {first, second});
      });
}

void populateMatchToLLVMConversionPatterns(const LLVMTypeConverter &converter,
                                           RewritePatternSet &patterns) {
  patterns.add<DeconstructOpLowering>(converter, patterns.getContext());
}

void configureMatchToLLVMConversionLegality(ConversionTarget &target) {
  target.addIllegalOp<MatchOp, GuardOp, YieldOp, DeconstructOp>();
  target.addLegalDialect<arith::ArithDialect, scf::SCFDialect,
                         LLVM::LLVMDialect>();
}

std::unique_ptr<Pass> createMatchToLLVMPass() {
  return std::make_unique<MatchToLLVMPass>();
}

} // namespace match

} // namespace mlir
