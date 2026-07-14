-module(errm_http_brotli_nif).
-export([compress/2, decompress/1]).
-on_load(init/0).

-spec init() -> ok.
init() ->
  Default = "./priv/errm_http_brotli_nif",

  NifPath = case code:priv_dir(errm_http) of
    PrivDir when is_list(PrivDir) ->
      filename:join([PrivDir, "errm_http_brotli_nif"]);
    {error, bad_name} ->
      logger:error("Could not find priv_dir"),
      case code:lib_dir(errm_http) of
        {ok, LibDir} ->
          filename:join([LibDir, "priv", "errm_http_brotli_nif"]);
        _ ->
          logger:error("Could not find lib_dir"),
          Default
      end;
    _ ->
      logger:error("Could not find priv_dir, and it wasnt bad_name"),
      Default
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
