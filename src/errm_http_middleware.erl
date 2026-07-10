-module(errm_http_middleware).
-export([run/3]).
-include("include/errm_http.hrl").

-spec run([middleware()], request(), fun(() -> route_result())) -> route_result().
run([], _Req, Next) ->
  Next();
run([Mw | Rest], Req, Next) ->
  Mw(Req, fun() -> run(Rest, Req, Next) end).
