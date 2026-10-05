-module(errm_http_acceptor).
-export([accept_loop/4]).
-include("include/errm_http.hrl").

-spec accept_loop(ListenSock :: gen_tcp:socket(), RouteTree :: route_trie_node(), Middlewares :: [middleware()], ErrorHandlers :: error_handler_map()) -> no_return().
accept_loop(ListenSock, RouteTree, Middlewares, ErrorHandlers) ->
  case gen_tcp:accept(ListenSock) of
    {ok, ClientSock} ->
      Peer = peer_address(ClientSock),
      HandlerPid = spawn_link(fun() ->
        receive go -> ok end,
        errm_http_handler:handle_connection(ClientSock, Peer, RouteTree, Middlewares, ErrorHandlers)
      end),

      ok = gen_tcp:controlling_process(ClientSock, HandlerPid),
      HandlerPid ! go,
      accept_loop(ListenSock, RouteTree, Middlewares, ErrorHandlers);
    {error, Reason} ->
      logger:error("[errm] Error accepting connection: ~p", [Reason]),
      accept_loop(ListenSock, RouteTree, Middlewares, ErrorHandlers)
  end.


-spec peer_address(gen_tcp:socket()) -> {inet:ip_address(), inet:port_number()}.
peer_address(Sock) ->
  case inet:peername(Sock) of
    {ok, {IP, Port}} -> from_peername({IP, Port});
    _ -> {{0,0,0,0}, 0}
  end.

from_peername({IP, Port}) when tuple_size(IP) =:= 4 -> {IP, Port};
from_peername({IP, Port}) when tuple_size(IP) =:= 8 -> {IP, Port};
from_peername(_) -> {{0,0,0,0}, 0}.
