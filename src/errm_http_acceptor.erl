-module(errm_http_acceptor).
-export([accept_loop/3]).
-include("include/errm_http.hrl").

-spec accept_loop(gen_tcp:socket(), route_trie_node(), [middleware()]) -> no_return().
accept_loop(ListenSock, RouteTree, Middleware) ->
  case gen_tcp:accept(ListenSock) of
    {ok, ClientSock} ->
      Peer = peer_address(ClientSock),
      ok = inet:setopts(ClientSock, [{active, once}, {packet, raw}, {nodelay, true}]),
      HandlerPid = spawn_link(fun() ->
        errm_http_handler:handle_connection(ClientSock, Peer, RouteTree, Middleware) end),

      gen_tcp:controlling_process(ClientSock, HandlerPid),
      accept_loop(ListenSock, RouteTree, Middleware);
    {error, _Reason} ->
      io:format("[errm] Error accepting connection: ~p ~n", [_Reason]),
      accept_loop(ListenSock, RouteTree, Middleware)
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
