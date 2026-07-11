-module(errm_http_zstd_nif).
-export([compress/2, decompress/1]).
-on_load(init/0).

-spec init() -> ok.
init() ->
  SoPath0 = case code:priv_dir(?MODULE) of
    {error, bad_name} -> filename:join([".", "priv", "errm_http_zstd_nif"]);
    PrivDir -> filename:join([PrivDir, "errm_http_zstd_nif"])
  end,

  SoPath = case SoPath0 of
    List when is_list(List) -> List;
    Binary when is_binary(Binary) -> erlang:binary_to_list(Binary)
  end,
  case erlang:load_nif(SoPath, 0) of
    ok -> ok;
    {error, {load_failed, _}} ->
      %% NIF not available - fallback to stubs.
      %% Return ok so the module loads without crashing.
      ok
  end.

-spec compress(Data :: binary(), Level :: 0..22) -> {ok, binary()}.
compress(_Data, _Level) -> erlang:nif_error(not_loaded).

-spec decompress(Data :: binary()) -> {ok, binary()}.
decompress(_Data) -> erlang:nif_error(not_loaded).
