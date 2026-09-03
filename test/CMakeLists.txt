add_custom_target(check-mlir-match
  COMMAND ${CMAKE_SOURCE_DIR}/.venv/bin/lit -sv ${CMAKE_CURRENT_SOURCE_DIR}
  DEPENDS match-opt
  COMMENT "Running the match dialect tests"
)
