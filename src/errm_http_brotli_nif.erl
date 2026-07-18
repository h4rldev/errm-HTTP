-module(errm_http_brotli_nif).
-export([compress/2, decompress/1]).
-on_load(init/0).

-spec init() -> ok.
init() ->
  Path = errm_http_nif_loader:path(errm_http, "errm_http_brotli_nif"),
  case erlang:load_nif(Path, 0) of
    ok -> ok;
    {error, Reason} -> erlang:error({nif_load_failed, Path, Reason})
  end.

-spec compress(Data :: binary(), Level :: 0..11) -> {ok, binary()}.
compress(_Data, _Level) -> erlang:nif_error(not_loaded).

-spec decompress(Data :: binary()) -> {ok, binary()}.
decompress(_Data) -> erlang:nif_error(not_loaded).
