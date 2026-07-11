-module(errm_http_handler).
-export([handle_connection/5]).
-include("include/errm_http.hrl").

-spec handle_connection(ClientSock :: gen_tcp:socket(), Peer :: {inet:ip_address(), inet:port_number()}, RouteTree :: route_trie_node(), Middlewares :: [middleware()], ErrorHandlers :: error_handler_map()) -> ok.
  handle_connection(ClientSock, Peer, RouteTree, Middlewares, ErrorHandlers) ->
    request_loop(ClientSock, Peer, RouteTree, Middlewares, ErrorHandlers, <<>>).

request_loop(ClientSock, Peer, RouteTree, Middlewares, ErrorHandlers, Buffer) ->
  receive
    {tcp, Sock, Data} ->
      NewBuffer = <<Buffer/binary, Data/binary>>,
      case handle_data(Sock, Peer, RouteTree, Middlewares, ErrorHandlers, NewBuffer) of
        {continue, Rest} ->
          inet:setopts(Sock, [{active, once}]),
          request_loop(ClientSock, Peer, RouteTree, Middlewares, ErrorHandlers, Rest);
        {close, _Rest} ->
          gen_tcp:close(Sock)
      end;
    {tcp_closed, _Sock} ->
      ok;
    {tcp_error, Sock, closed} ->
      gen_tcp:close(Sock);
    {tcp_error, Sock, Reason} ->
      io:format("[errm] Error handling connection: ~p ~n", [Reason]),
      gen_tcp:close(Sock)
  end.

handle_data(Sock, Peer, RouteTree, Middlewares, ErrorHandlers, Data) ->
  case errm_http_request:parse(Data) of
    {ok, Request, Rest} ->
      Request2 = Request#{peer => Peer},
      Result = errm_http_middleware:run(Middlewares, Request2, fun(Req) ->
        errm_http_router:dispatch(RouteTree, Req)
      end),

      send_response(Sock, ErrorHandlers, Result, Request2),
      Conn = maps:get(connection, maps:get(headers, Request2, #{}), keep_alive),
      case normalize_conn(Conn) of
        keep_alive -> {continue, Rest};
        close -> {close, Rest}
      end;

    {partial, _} ->
      {continue, Data};
    {error, _Reason} ->
      send_response(Sock, ErrorHandlers, {error, bad_request}, undefined),
      {close, Data}
  end.


send_response(Sock, _ErrorHandlers, {ok, {Status, Headers, Body}}, _Request) ->
  BodySize = iolist_size(Body),
  Normalized = normalize_headers(Headers),
  HasTE = maps:is_key(~"transfer-encoding", Normalized),
  HasCL = maps:is_key(~"content-length", Normalized),
  case not HasTE andalso not HasCL andalso BodySize >= 8192 of
    true ->
      gen_tcp:send(Sock, errm_http_response:build_headers(Status, Headers, BodySize)),
      send_chunked(Sock, iolist_to_binary(Body), 4096),
      gen_tcp:send(Sock, errm_http_response:final_chunk());
    false ->
      gen_tcp:send(Sock, errm_http_response:build(Status, Headers, Body))
  end;

send_response(Sock, ErrorHandler, {error, Reason}, Request) ->
    case maps:get(Reason, ErrorHandler, undefined) of
        undefined ->
            send_default_error(Sock, Reason);
        Handler ->
            case Handler(Request) of
                {ok, {Status, Headers, Body}} ->
                  BodySize = iolist_size(Body),
                  Normalized = normalize_headers(Headers),
                  HasTE = maps:is_key(~"transfer-encoding", Normalized),
                  HasCL = maps:is_key(~"content-length", Normalized),
                  case not HasTE andalso not HasCL andalso BodySize >= 8192 of
                    true ->
                      gen_tcp:send(Sock, errm_http_response:build_headers(Status, Headers, BodySize)),
                      send_chunked(Sock, iolist_to_binary(Body), 4096),
                      gen_tcp:send(Sock, errm_http_response:final_chunk());
                    false ->
                      gen_tcp:send(Sock, errm_http_response:build(Status, Headers, Body))
                  end;
                _ ->
                    send_default_error(Sock, Reason)
            end
    end.

normalize_conn(Conn) when is_binary(Conn) ->
    case string:lowercase(Conn) of
        ~"close" -> close;
        _           -> keep_alive
    end;
normalize_conn(Conn) when is_list(Conn) ->
    case string:lowercase(Conn) of
        "close" -> close;
        _       -> keep_alive
    end;
normalize_conn(Atom) when is_atom(Atom) ->
    case Atom of
        close -> close;
        _     -> keep_alive
    end;
normalize_conn(_) ->
    keep_alive.

send_chunked(_Sock, <<>>, _ChunkSize) -> ok;
send_chunked(Sock, Body, ChunkSize) ->
  case byte_size(Body) =< ChunkSize of
    true ->
      gen_tcp:send(Sock, errm_http_response:encode_chunk(Body));
    false ->
      <<Chunk:ChunkSize/binary, Rest/binary>> = Body,
      gen_tcp:send(Sock, errm_http_response:encode_chunk(Chunk)),
      send_chunked(Sock, Rest, ChunkSize)
  end.

normalize_headers(Headers) ->
  maps:fold(fun(K, V, Acc) ->
    Acc#{string:lowercase(to_binary(K)) => to_binary(V)}
  end, #{}, Headers).

to_binary(S) when is_list(S) -> list_to_binary(S);
to_binary(S) -> S.

send_default_error(Sock, not_found) ->
    B = <<"Not Found">>,
    gen_tcp:send(Sock, errm_http_response:build(404, #{"content-type" => "text/plain", "content-length" => integer_to_binary(byte_size(B)), "connection" => "close"}, B));
send_default_error(Sock, method_not_allowed) ->
    B = <<"Method Not Allowed">>,
    gen_tcp:send(Sock, errm_http_response:build(405, #{"content-type" => "text/plain", "content-length" => integer_to_binary(byte_size(B)), "connection" => "close"}, B));
send_default_error(Sock, internal_error) ->
    B = <<"Internal Server Error">>,
    gen_tcp:send(Sock, errm_http_response:build(500, #{"content-type" => "text/plain", "content-length" => integer_to_binary(byte_size(B)), "connection" => "close"}, B));
send_default_error(Sock, bad_request) ->
    B = <<"Bad Request">>,
    gen_tcp:send(Sock, errm_http_response:build(400, #{"content-type" => "text/plain", "content-length" => integer_to_binary(byte_size(B)), "connection" => "close"}, B));
send_default_error(Sock, _) ->
    B = <<"Internal Server Error">>,
    gen_tcp:send(Sock, errm_http_response:build(500, #{"content-type" => "text/plain", "content-length" => integer_to_binary(byte_size(B)), "connection" => "close"}, B)).
