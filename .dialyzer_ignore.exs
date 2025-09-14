[
  # The error pattern in persistence_handler.ex is defensive programming
  # against potential future changes to the create_snapshot implementation.
  # While currently unreachable based on code flow, it should be kept
  # for robustness.
  {"lib/poker_server/tournament/persistence_handler.ex", "The pattern can never match the type {:error, _}."},
  
  # The else clause in application.ex is unreachable in dev environment  
  # where persistence_module is compile-time determined to be ProductionPersistence.
  # This is expected behavior but needed for test environment compatibility.
  {"lib/poker_server/application.ex", "The pattern can never match the type true."}
]