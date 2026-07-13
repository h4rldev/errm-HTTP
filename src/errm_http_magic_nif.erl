-module(errm_http_magic_nif).
-export([get_mime_type/1]).
-on_load(init/0).

-spec init() -> ok.
init() ->
  NifPath = case code:priv_dir(errm_http) of
    Dir when is_list(Dir) -> filename:join(Dir, "errm_http_magic_nif");
    _ -> {error, nif_not_found}
  end,
  NifPathStr = case NifPath of
    Path when is_list(Path) -> Path
  end,
  ok = erlang:load_nif(NifPathStr, 0),
  ok.

-spec get_mime_type(FilePath :: string()) -> {ok, string()}.
get_mime_type(_FilePath) ->
  erlang:nif_error(not_loaded).

