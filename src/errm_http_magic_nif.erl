-module(errm_http_magic_nif).
-export([get_mime_type/1]).
-on_load(init/0).

-spec init() -> ok.
init() ->
  SoPath0 = case code:priv_dir(?MODULE) of
    {error, bad_name} -> filename:join([".", "priv", "errm_http_magic_nif"]);
    PrivDir -> filename:join([PrivDir, "errm_http_magic_nif"])
  end,

  SoPath = case SoPath0 of
    List when is_list(List) -> List;
    Binary when is_binary(Binary) -> erlang:binary_to_list(Binary)
  end,
  ok = erlang:load_nif(SoPath, 0).

-spec get_mime_type(FilePath :: string()) -> {ok, string()}.
get_mime_type(_FilePath) ->
  erlang:nif_error(not_loaded).

