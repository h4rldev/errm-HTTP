-module(errm_http_middleware).
-export([run/3]).
-include("include/errm_http.hrl").

-spec run(Middlewares :: [middleware()], Request:: request(), NextFunction :: next_fun()) -> RouteRes :: route_result().
run([], Request, NextFunction) ->
    NextFunction(Request);
run([Middleware | Rest], Request, NextFunction) ->
    Middleware(Request, fun(Req1) -> run(Rest, Req1, NextFunction) end).
