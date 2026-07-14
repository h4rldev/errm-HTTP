-module(errm_http_magic_nif).
-export([get_mime_type/1]).
-on_load(init/0).

-spec init() -> ok.
init() ->
  Default = "./priv/errm_http_magic_nif",

  NifPath = case code:priv_dir(errm_http) of
    PrivDir when is_list(PrivDir) ->
      filename:join([PrivDir, "errm_http_magic_nif"]);
    {error, bad_name} ->
      logger:error("Could not find priv_dir"),
      case code:lib_dir(errm_http) of
        {ok, LibDir} ->
          filename:join([LibDir, "priv", "errm_http_magic_nif"]);
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
      {error, Reason} -> erlang:error({nif_load_failed, Reason})
    end.

-spec get_mime_type(FilePath :: string()) -> {ok, string()}.
get_mime_type(_FilePath) ->
  erlang:nif_error(not_loaded).

