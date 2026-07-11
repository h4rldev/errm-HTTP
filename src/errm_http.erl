-module(errm_http).
-export([start/1, stop/0]).
-export([set_secret/2, get_secret/1, delete_secret/1, get_all_secrets/0]).
-export_type([options/0]).
-include("include/errm_http.hrl").

-spec start(Options :: options()) -> {ok, pid()} | {error, term()}.
start(Options) ->
  case errm_http_sup:start_link(Options) of
    {ok, Pid} -> {ok, Pid};
    {error, Reason} -> {error, Reason}
  end.

-spec stop() -> ok.
stop() ->
  errm_http_sup:stop().


-spec set_secret(Key :: term(), Value :: term()) -> ok.
set_secret(Key, Value) ->
    Map0 = persistent_term:get(?MODULE_SECRETS, #{}),
    Map1 = case Map0 of
        M when is_map(M) -> M#{Key => Value};
        _ -> #{}
    end,
    persistent_term:put(?MODULE_SECRETS, Map1),
    ok.

-spec get_secret(Key :: term()) -> {ok, term()} | {error, not_found}.
get_secret(Key) ->
  Map = persistent_term:get(?MODULE_SECRETS, #{}),
  case Map of
    M when is_map(M) ->
      case maps:is_key(Key, M) of
        true -> {ok, maps:get(Key, M)};
        false -> {error, not_found}
      end;
    _ -> {error, not_found}
  end.

-spec delete_secret(Key :: term()) -> ok.
delete_secret(Key) ->
  Map0 = persistent_term:get(?MODULE_SECRETS, #{}),
  Map1 = case Map0 of
    M when is_map(M) -> maps:remove(Key, M);
    _ -> #{}
  end,
  persistent_term:put(?MODULE_SECRETS, Map1),
  ok.

-spec get_all_secrets() -> #{term() => term()}.
get_all_secrets() ->
  case persistent_term:get(?MODULE_SECRETS, #{}) of
    M when is_map(M) -> M;
    _ -> #{}
  end.
