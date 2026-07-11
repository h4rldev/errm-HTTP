-module(errm_http_demo).
-export([start/0, start/1, stop/0, main/1]).

main(Args) ->
  Port = case Args of
    [PortStr] -> list_to_integer(PortStr);
    _ -> 8080
  end,
  start(Port),
  receive
    stop -> stop()
  end.

-spec start() -> {ok, pid()}.
start() ->
  start(8080).

-spec start(pos_integer()) -> {ok, pid()}.
start(Port) ->
  Routes = [
    {get, [":path*"], errm_http_file:serve_dir("site-root")},
    {get, ["hello"], fun hello_handler/1},
    {get, ["users", ":id"], fun user_handler/1},
    {get, ["set-cookie", ":value"], fun set_cookie_handler/1},
    {get, ["set-cookie-signed", ":value"], fun set_cookie_signed_handler/1},
    {get, ["get-cookie"], fun get_cookie_handler/1}
  ],

  CORS = errm_http_cors:make(#{
    origins => "*",
    methods => [get, post, put, delete, patch, options],
    headers => ["Content-Type", "Authorization", "Accept", "Origin"],
    exposed_headers => [],
    credentials => false,
    max_age => 86400
  }),
  COOKIE = errm_http_cookie:with_cookies(),
  COMPRESSION = errm_http_compress:compress(#{
      preferred => [deflate, zstd, brotli],
      level => 9,
      min_length => 1
  }),
  DECOMPRESSION = errm_http_compress:decompress(#{
      allowed => [gzip, deflate, zstd, brotli]
  }),

  errm_http:set_secret(secret, crypto:strong_rand_bytes(32)),
  {ok, Pid} = errm_http:start(#{
      server_name => "errm... HTTP!",
      port => Port,
      routes => Routes,
      middleware => [DECOMPRESSION, CORS, COOKIE, COMPRESSION]
  }),

  io:format("Server started at http://localhost:~B/~n", [Port]),
  io:format("\t GET /                         -> index~n"),
  io:format("\t GET /hello                    -> hello~n"),
  io:format("\t GET /users/:id                -> Get a user~n"),
  io:format("\t GET /set-cookie/:value        -> Set a cookie~n"),
  io:format("\t GET /set-cookie-signed/:value -> Set a signed cookie~n"),
  io:format("\t GET /get-cookie               -> Get the cookie values you set~n"),

  {ok, Pid}.

stop() ->
  errm_http:stop(),
  io:format("Server stopped~n").

%% index_handler(_Req) -> {ok, {200, #{"content-type" => "text/html"}, "<h1>Hello World, This server is running on errm... HTTP!</h1>"}}.
hello_handler(_Req) -> {ok, {200, #{"content-type" => "text/plain"}, "Hello, World!"}}.
user_handler(#{params := #{"id" := Id}}) ->
  Id1 = binary_to_integer(Id),
  {ok, {200, #{"content-type" => "text/plain"}, io_lib:format("You're currently viewing User: ~w", [Id1])}}.


set_cookie_handler(Req) ->
    Params = maps:get(params, Req, #{}),
    Value = maps:get(<<"value">>, Params, <<>>),

    Jar0 = errm_http_cookie_jar:new(),
    Jar1 = errm_http_cookie_jar:put(Jar0, <<"test_unsigned">>, Value, #{
      signed => false,
      path => <<"/">>,
      domain => <<"localhost">>,
      max_age => 86400
    }),
    CookieHeaders = errm_http_cookie_jar:to_headers(Jar1, undefined),

    Response = errm_http_cookie:add_cookies(
        {200, #{<<"content-type">> => <<"text/plain">>}, <<"Unsigned cookie set!">>},
        CookieHeaders
    ),
    {ok, Response}.

set_cookie_signed_handler(Req) ->
    Params = maps:get(params, Req, #{}),
    Value = maps:get(<<"value">>, Params, <<>>),

    Jar0 = errm_http_cookie_jar:new(),
    Jar1 = errm_http_cookie_jar:put(Jar0, <<"test_signed*">>, Value, #{
      signed => true,
      path => <<"/">>,
      domain => <<"localhost">>,
      max_age => 86400
    }),

    {ok, Secret} = errm_http:get_secret(secret),
    CookieHeaders = errm_http_cookie_jar:to_headers(Jar1, Secret),

    Response = errm_http_cookie:add_cookies(
        {200, #{<<"content-type">> => <<"text/plain">>}, <<"Signed cookie set!">>},
        CookieHeaders
    ),
    {ok, Response}.

get_cookie_handler(Req) ->
    RawCookies = maps:get(cookies, Req, #{}),
    io:format("Raw cookies: ~p~n", [RawCookies]),

    {ok, Secret} = errm_http:get_secret(secret),
    Jar = errm_http_cookie_jar:from_request(Req, Secret),

    Unsigned = errm_http_cookie_jar:get(Jar, <<"test_unsigned">>),
    Signed = errm_http_cookie_jar:get(Jar, <<"test_signed*">>),

    Body = io_lib:format("Unsigned: ~p, Signed: ~p", [Unsigned, Signed]),
    {ok, {200, #{<<"content-type">> => <<"text/plain">>}, Body}}.
