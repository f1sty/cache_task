import Config

config :cache, Cache.Store,
  ets_opts: [:named_table, :set, write_concurrency: true],
  name: Cache.Store

config :cache, Cache.FunctionsRegistry,
  ets_opts: [:named_table, :set],
  name: Cache.FunctionsRegistry
