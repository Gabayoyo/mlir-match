// match-opt: an mlir-opt-style driver for the match dialect
#include "mlir/IR/DialectRegistry.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "mlir/InitAllDialects.h"

#include "Match/MatchDialect.h"

int main(int argc, char **argv) {
  mlir::DialectRegistry registry;
  mlir::registerAllDialects(registry);
  registry.insert<mlir::match::MatchDialect>();

  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "match-opt", registry));
}
