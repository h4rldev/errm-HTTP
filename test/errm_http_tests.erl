-module(errm_http_tests).
-include_lib("eunit/include/eunit.hrl").

parse_get_test() ->
    Data = ~"GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n",
    {ok, #{method := get, path := [~"hello"]} = Req, <<>>} = errm_http_request:parse(Data),
    ?assertEqual(~"localhost", maps:get(~"host", maps:get(headers, Req), undefined)).

parse_post_with_body_test() ->
    Body = ~"{\"key\":\"val\"}",
    Data = <<"POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: 13\r\n\r\n", Body/binary>>,
    {ok, #{method := post, body := Body, path := [~"echo"]}, <<>>} = errm_http_request:parse(Data).

parse_partial_test() ->
    Data = ~"GET /hello HTTP/1.1\r\n",
    {partial, <<>>} = errm_http_request:parse(Data).

parse_post_chunked_body_test() ->
    Data = ~"POST /echo HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n20\r\n0\r\n\r\n",
    {ok, #{method := post, body := ~"20", path := [~"echo"]}, <<>>} = errm_http_request:parse(Data).

parse_chunked_multiple_chunks_test() ->
    Data = ~"POST /echo HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n",
    {ok, #{body := ~"hello world"}, <<>>} = errm_http_request:parse(Data).

parse_chunked_extensions_and_trailers_test() ->
    Data = ~"POST /echo HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n2;foo=bar\r\n20\r\n0\r\nX-Trailer: done\r\n\r\n",
    {ok, #{body := ~"20"}, <<>>} = errm_http_request:parse(Data).

parse_chunked_partial_data_test() ->
    Data = ~"POST /echo HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhe",
    {partial, _} = errm_http_request:parse(Data).

parse_chunked_keeps_pipelined_request_test() ->
    Data = ~"POST /echo HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n20\r\n0\r\n\r\nGET /next HTTP/1.1\r\nHost: localhost\r\n\r\n",
    {ok, #{body := ~"20"}, Rest} = errm_http_request:parse(Data),
    {ok, #{method := get, path := [~"next"]}, <<>>} = errm_http_request:parse(Rest).

parse_chunked_takes_precedence_over_content_length_test() ->
    Data = ~"POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: 99\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n20\r\n0\r\n\r\n",
    {ok, #{body := ~"20"}, <<>>} = errm_http_request:parse(Data).

parse_bad_chunk_size_test() ->
    Data = ~"POST /echo HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n\r\n",
    ?assertMatch({error, _}, errm_http_request:parse(Data)).

parse_bad_method_test() ->
    Data = ~"INVALID /path HTTP/1.1\r\n\r\n",
    {error, bad_request_line} = errm_http_request:parse(Data).


ping_handler(_Req) -> {ok, {200, #{}, ~"pong"}}.

router_static_match_test() ->
    Routes = errm_http_router:compile([{get, [~"ping"], fun ping_handler/1}]),
    Req = #{method => get, path => [~"ping"], raw_path => ~"/ping",  params => #{}, headers => #{},
            body => <<>>, peer => {{127,0,0,1}, 12345}, cookies => #{}},
    {ok, {200, _, ~"pong"}} = errm_http_router:dispatch(Routes, Req).

router_dynamic_param_test() ->
    Routes = errm_http_router:compile([{get, [~"users", ~":id"], fun user_handler/1}]),
    Req = #{method => get, path => [~"users", ~"42"], raw_path => ~"/users/42", params => #{},
            headers => #{}, body => <<>>, peer => {{127,0,0,1}, 12345}, cookies => #{}},
    case errm_http_router:dispatch(Routes, Req) of
      {ok, {200, _, ~"User: 42"}} -> ok;
      {error, internal_error} = Err -> Err
    end.

user_handler(#{params := #{~"id" := Id}}) ->
    {ok, {200, #{}, <<"User: ", Id/binary>>}}.

router_not_found_test() ->
    Routes = errm_http_router:compile([{get, [~"ping"], fun ping_handler/1}]),
    Req = #{method => get, path => [~"nope"], raw_path => ~"/nope", params => #{}, headers => #{},
            body => <<>>, peer => {{127,0,0,1}, 12345}, cookies => #{}},
    {error, not_found} = errm_http_router:dispatch(Routes, Req).

router_method_not_allowed_test() ->
    Routes = errm_http_router:compile([{get, [~"ping"], fun ping_handler/1}]),
    Req = #{method => post, path => [~"ping"], raw_path => ~"/ping", params => #{}, headers => #{},
            body => <<>>, peer => {{127,0,0,1}, 12345}, cookies => #{}},
    {error, method_not_allowed} = errm_http_router:dispatch(Routes, Req).

response_build_test() ->
    Bin = errm_http_response:build(200, #{~"content-type" => ~"text/plain"}, ~"OK"),
    ?assertNotEqual(nomatch, binary:match(Bin, ~"HTTP/1.1 200 OK\r\n")),
    ?assertNotEqual(nomatch, binary:match(Bin, ~"content-type: text/plain\r\n")).

response_adds_content_length_test() ->
    Bin = errm_http_response:build(200, #{~"x-foo" => ~"bar"}, ~"hello"),
    ?assertNotEqual(nomatch, binary:match(Bin, ~"content-length: 5\r\n")).


middleware_passthrough_test() ->
    Req = #{method => get, path => [], raw_path => ~"/", params => #{}, peer => {{0,0,0,0}, 0}, headers => #{}, body => <<>>, cookies => #{}}, 
    Result = errm_http_middleware:run([], Req, fun(_Req1) -> {ok, {200, #{}, ~"ok"}} end),
    ?assertEqual({ok, {200, #{}, ~"ok"}}, Result).

middleware_adds_header_test() ->
    AddHeader = fun(_Req, Next) ->
        case Next(_Req) of
            {ok, {Status, H, Body}} ->
                {ok, {Status, H#{~"x-middleware" => ~"yes"}, Body}};
            Other -> Other
        end
    end,
    Result = errm_http_middleware:run([AddHeader], #{method => get, path => [], raw_path => ~"/", params => #{}, peer => {{0,0,0,0}, 0}, headers => #{}, body => <<>>, cookies => #{}},
        fun(_Req) -> {ok, {200, #{}, ~"body"}} end),
    ?assertMatch({ok, {200, #{~"x-middleware" := ~"yes"}, ~"body"}}, Result).


cors_simple_request_test() ->
    CORS = errm_http_cors:make(#{origin => ~"*", credentials => true, methods => [get, post], max_age => 86400, exposed_headers => [], headers => [] }),
    Req = #{method => get, path => [~"test"], raw_path => ~"/test",
            headers => #{~"origin" => ~"https://example.com"},
            body => <<>>, params => #{}, peer => {{127,0,0,1},12345}, cookies => #{}},
    Next = fun(_Req) -> {ok, {200, #{~"x-foo" => ~"bar"}, ~"body"}} end,
    {ok, {200, Headers, ~"body"}} = CORS(Req, Next),
    ?assertEqual(~"*", maps:get(~"access-control-allow-origin", Headers)),
    ?assertEqual(~"Origin", maps:get(~"vary", Headers)).

cors_preflight_test() ->
    CORS = errm_http_cors:make(#{origin => ~"*", credentials => true, methods => [get, post], max_age => 86400, exposed_headers => [], headers => []}),
    Req = #{method => options, path => [~"test"], raw_path => ~"/test",
            headers => #{~"origin" => ~"https://example.com",
                        ~"access-control-request-headers" => ~"Content-Type"},
            body => <<>>, params => #{}, peer => {{127,0,0,1},12345}, cookies => #{}},
    {ok, {204, Headers, <<>>}} = CORS(Req, fun(_Req) -> {error, should_not_reach} end),
    ?assertEqual(~"*", maps:get(~"access-control-allow-origin", Headers)),
    ?assert(maps:is_key(~"access-control-allow-methods", Headers)).

cors_origin_denied_test() ->
    CORS = errm_http_cors:make(#{origin => [~"https://trusted.com"], credentials => true, methods => [get, post], max_age => 86400, exposed_headers => [], headers => []}),
    Req = #{method => get, path => [~"test"], raw_path => ~"/test",
            headers => #{~"origin" => ~"https://evil.com"},
            body => <<>>, params => #{}, peer => {{127,0,0,1},12345}, cookies => #{}},
    {ok, {200, Headers, _}} = CORS(Req, fun(_Req) -> {ok, {200, #{}, ~"body"}} end),
    ?assertNot(maps:is_key(~"access-control-allow-origin", Headers)).

file_serve_dir_prefers_compressed_variant_test() ->
    errm_http_file:init_mime_cache(),
    Base = filename:join(tmp_dir(), "errm_http_test_" ++ integer_to_list(erlang:unique_integer([positive]))),
    Root = filename:join(Base, "root"),
    ok = file:make_dir(Base),
    ok = file:make_dir(Root),
    Plain = ~"body{color:red}",
    Brotli = <<1, 2, 3, 4, 5>>,
    ok = file:write_file(filename:join(Root, "app.css"), Plain),
    ok = file:write_file(filename:join(Root, "app.css.br"), Brotli),
    Handler = errm_http_file:serve_dir(Root, ["index.html"], "200.html"),
    try
        ?assertMatch(
            {ok, {200, #{~"content-encoding" := ~"br"}, Brotli}},
            Handler(#{params => #{"path" => ~"app.css"},
                      headers => #{~"accept-encoding" => ~"gzip, deflate, br"}})),
        {ok, {200, HeadersPlain, Plain}} =
            Handler(#{params => #{"path" => ~"app.css"}, headers => #{}}),
        ?assertNot(maps:is_key(~"content-encoding", HeadersPlain)),
        {ok, {200, HeadersGzip, Plain}} =
            Handler(#{params => #{"path" => ~"app.css"},
                      headers => #{~"accept-encoding" => ~"gzip"}}),
        ?assertNot(maps:is_key(~"content-encoding", HeadersGzip))
    after
        file:delete(filename:join(Root, "app.css.br")),
        file:delete(filename:join(Root, "app.css")),
        file:del_dir(Root),
        file:del_dir(Base)
    end.

file_serve_dir_blocks_traversal_test() ->
    errm_http_file:init_mime_cache(),
    Base = filename:join(tmp_dir(), "errm_http_test_" ++ integer_to_list(erlang:unique_integer([positive]))),
    Root = filename:join(Base, "root"),
    ok = file:make_dir(Base),
    ok = file:make_dir(Root),
    ok = file:write_file(filename:join(Base, "secret.txt"), ~"top secret"),
    ok = file:write_file(filename:join(Root, "hello.txt"), ~"public"),
    Handler = errm_http_file:serve_dir(Root, ["index.html"]),
    try
        ?assertMatch({ok, {200, _, ~"public"}},
            Handler(#{params => #{"path" => ~"hello.txt"}, headers => #{}})),
        ?assertEqual({error, not_found},
            Handler(#{params => #{"path" => ~"../secret.txt"}, headers => #{}}))
    after
        file:delete(filename:join(Root, "hello.txt")),
        file:delete(filename:join(Base, "secret.txt")),
        file:del_dir(Root),
        file:del_dir(Base)
    end.

tmp_dir() ->
    case os:getenv("TMPDIR") of
        false -> "/tmp";
        Dir -> Dir
    end.
