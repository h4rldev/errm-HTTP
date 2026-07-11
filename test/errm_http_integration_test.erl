-module(errm_http_integration_test).
-include_lib("eunit/include/eunit.hrl").

-spec start(pos_integer()) -> pos_integer().
start(Port) ->
  Routes = [
    {get, [~"hello"], fun hello_handler/1},
    {post, [~"echo"], fun echo_handler/1},
    {get, [~"users", ~":id"], fun user_handler/1}
  ],
  {ok, _Pid} = errm_http:start(#{port => Port, routes => Routes}),
  timer:sleep(100),
  Port.

stop(_) ->
    errm_http:stop().

hello_handler(_Req) -> {ok, {200, #{~"content-type" => ~"text/plain"}, ~"hello"}}.

echo_handler(#{body := Body}) ->
  {ok, {200, #{~"content-type" => ~"application/octet-stream"}, Body}}.

user_handler(#{params := #{~"id" := Id}}) ->
  {ok, {200, #{~"content-type" => ~"text/plain"}, <<"User: ", Id/binary>>}}.


integration_test_() ->
    Port = 16890,
    {setup,
     fun() -> start(Port) end,
     fun stop/1,
     [fun() -> test_get(Port) end,
      fun() -> test_post_echo(Port) end,
      fun() -> test_user_param(Port) end,
      fun() -> test_404(Port) end,
      fun() -> test_keepalive(Port) end]}.

test_get(Port) ->
    {ok, {200, _Headers, ~"hello"}} = raw_request(Port, ~"GET /hello HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n").

test_post_echo(Port) ->
    Body = ~"Hello Echo!",
    Req = [~"POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: ",
           integer_to_binary(byte_size(Body)),
           ~"\r\nConnection: close\r\n\r\n", Body],
    {ok, {200, _Headers, Body}} = raw_request(Port, Req).

test_user_param(Port) ->
    case raw_request(Port, ~"GET /users/42 HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n") of
      {ok, {200, _Headers, ~"User: 42"}} -> ok;
      {ok, {500, _Headers, ~"Internal Server Error"}} -> {error, internal_error}
    end.

test_404(Port) ->
    {ok, {404, _Headers, _Body}} = raw_request(Port, ~"GET /nonexistent HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n").

test_keepalive(Port) ->
    {ok, Sock} = gen_tcp:connect({127,0,0,1}, Port, [binary, {active, false}, {packet, raw}], 3000),
    ok = gen_tcp:send(Sock, ~"GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n"),
    {ok, Resp1} = recv_response(Sock),
    ?assertMatch({200, _, ~"hello"}, Resp1),
    ok = gen_tcp:send(Sock, ~"GET /users/99 HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"),
    {ok, Resp2} = recv_response(Sock),
    ?assertMatch({200, _, ~"User: 99"}, Resp2),
    gen_tcp:close(Sock).


raw_request(Port, Data) ->
    {ok, Sock} = gen_tcp:connect({127,0,0,1}, Port, [binary, {active, false}, {packet, raw}], 3000),
    ok = gen_tcp:send(Sock, Data),
    Result = recv_response(Sock),
    gen_tcp:close(Sock),
    Result.

recv_response(Sock) ->
    recv_response(Sock, <<>>).

recv_response(Sock, Acc) ->
    case gen_tcp:recv(Sock, 0, 3000) of
        {ok, Data} when is_binary(Data) ->
            case binary:split(<<Acc/binary, Data/binary>>, ~"\r\n\r\n") of
                [Hdrs, Body] ->
                    Status = parse_status(Hdrs),
                    {ok, {Status, #{}, Body}};
                [_] ->
                    recv_response(Sock, <<Acc/binary, Data/binary>>)
            end;
        {error, closed} ->
            {error, closed}
    end.

parse_status(Hdrs) ->
    [StatusLine | _] = binary:split(Hdrs, ~"\r\n", [global]),
    [_HttpVer, Code | _] = binary:split(StatusLine, ~" ", [global]),
    binary_to_integer(Code).
