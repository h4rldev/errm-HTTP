-module(errm_http_magic_nif).
-export([get_mime_type/1]).
-on_load(init/0).

-spec init() -> ok.
init() ->
  Path = errm_http_nif_loader:path(errm_http, "errm_http_magic_nif"),
  case erlang:load_nif(Path, 0) of
    ok -> ok;
    {error, Reason} -> erlang:error({nif_load_failed, Path, Reason})
  end.

-spec get_mime_type(FilePath :: string()) -> {ok, string()}.
get_mime_type(_FilePath) ->
  erlang:nif_error(not_loaded).

