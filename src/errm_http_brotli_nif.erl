-module(errm_http_brotli_nif).
-export([compress/2, decompress/1]).
-on_load(init/0).

-spec init() -> ok.
init() ->
  NifPath = case code:priv_dir(errm_http) of
    Dir when is_list(Dir) -> filename:join(Dir, "errm_http_brotli_nif");
    _ -> {error, nif_not_found}
  end,
  NifPathStr = case NifPath of
    Path when is_list(Path) -> Path
  end,
  case erlang:load_nif(NifPathStr, 0) of
    ok -> ok;
    {error, {load_failed, _}} ->
      %% NIF not available - fallback to stubs.
      %% Return ok so the module loads without crashing.
      ok
  end.

-spec compress(Data :: binary(), Level :: 0..11) -> {ok, binary()}.
compress(_Data, _Level) -> erlang:nif_error(not_loaded).

-spec decompress(Data :: binary()) -> {ok, binary()}.
decompress(_Data) -> erlang:nif_error(not_loaded).
