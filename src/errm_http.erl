-module(errm_http).
-export([start/1, stop/0]).
-include("include/errm_http.hrl").

-spec start(options()) -> {ok, pid()} | {error, term()}.
start(Options) ->
  case errm_http_sup:start_link(Options) of
    {ok, Pid} -> {ok, Pid};
    {error, Reason} -> {error, Reason}
  end.

-spec stop() -> ok.
stop() ->
  errm_http_sup:stop().
