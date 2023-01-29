import Config

config Cache.Store,
  ets_opts: [:named_table, :set, write_concurrency: true],
  name: Cache.Store

config Cache.FunctionsRegistry,
  ets_opts: [:named_table, :set],
  name: Cache.FunctionsRegistry
