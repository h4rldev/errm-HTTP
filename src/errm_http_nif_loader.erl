-module(errm_http_nif_loader).
-export([path/2]).

-define(CACHE_KEY, {?MODULE, extracted_root}).

path(Module, BaseName) ->
  case code:priv_dir(Module) of
    {error, bad_name} ->
      Root = ensure_extracted(),
      filename:join([Root, "lib", atom_to_list(Module), "priv", BaseName]);
    PrivDir when is_list(PrivDir) ->
      filename:join([PrivDir, BaseName])
  end.

ensure_extracted() ->
  case persistent_term:get(?CACHE_KEY, undefined) of
    undefined ->
      Script = escript:script_name(),
      {ok, Root} = escript:extract(Script, []),
      persistent_term:put(?CACHE_KEY, Root),
      Root;
    Root ->
      Root
  end.
