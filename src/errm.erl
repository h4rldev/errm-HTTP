-module(errm).
-export([start/1, stop/0]).
-include("errm.hrl").

-spec start(options()) -> {ok, pid()} | {error, term()}.
start(Options) ->
  case errm_sup:start_link(Options) of
    {ok, Pid} -> {ok, Pid};
    {error, Reason} -> {error, Reason}
  end.

-spec stop() -> ok.
stop() ->
  errm_sup:stop().
