-module(errm_unit_test).
-include_lib("eunit/include/eunit.hrl").

%% ── errm_request:parse/1 ───────────────────────────────────────────

parse_get_test() ->
    Data = ~"GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n",
    {ok, #{method := get, path := [~"hello"]} = Req, <<>>} = errm_request:parse(Data),
    ?assertEqual(~"localhost", maps:get(~"host", maps:get(headers, Req), undefined)).

parse_post_with_body_test() ->
    Body = ~"{\"key\":\"val\"}",
    Data = <<"POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: 13\r\n\r\n", Body/binary>>,
    {ok, #{method := post, body := Body, path := [~"echo"]}, <<>>} = errm_request:parse(Data).

parse_partial_test() ->
    Data = ~"GET /hello HTTP/1.1\r\n",
    {partial, <<>>} = errm_request:parse(Data).

parse_bad_method_test() ->
    Data = ~"INVALID /path HTTP/1.1\r\n\r\n",
    {error, bad_request_line} = errm_request:parse(Data).

%% ── errm_router:compile/1 + dispatch/2 ─────────────────────────────

ping_handler(_Req) -> {ok, {200, #{}, ~"pong"}}.

router_static_match_test() ->
    Routes = errm_router:compile([{get, [~"ping"], fun ping_handler/1}]),
    Req = #{method => get, path => [~"ping"], raw_path => ~"/ping",  params => #{}, headers => #{},
            body => <<>>, peer => {{127,0,0,1}, 12345}},
    {ok, {200, _, ~"pong"}} = errm_router:dispatch(Routes, Req).

router_dynamic_param_test() ->
    Routes = errm_router:compile([{get, [~"users", ~":id"], fun user_handler/1}]),
    Req = #{method => get, path => [~"users", ~"42"], raw_path => ~"/users/42", params => #{},
            headers => #{}, body => <<>>, peer => {{127,0,0,1}, 12345}},
    {ok, {200, _, ~"User: 42"}} = errm_router:dispatch(Routes, Req).

user_handler(#{params := #{~"id" := Id}}) ->
    {ok, {200, #{}, <<"User: ", Id/binary>>}}.

router_not_found_test() ->
    Routes = errm_router:compile([{get, [~"ping"], fun ping_handler/1}]),
    Req = #{method => get, path => [~"nope"], raw_path => ~"/nope", params => #{}, headers => #{},
            body => <<>>, peer => {{127,0,0,1}, 12345}},
    {error, not_found} = errm_router:dispatch(Routes, Req).

router_method_not_allowed_test() ->
    Routes = errm_router:compile([{get, [~"ping"], fun ping_handler/1}]),
    Req = #{method => post, path => [~"ping"], raw_path => ~"/ping", params => #{}, headers => #{},
            body => <<>>, peer => {{127,0,0,1}, 12345}},
    {error, method_not_allowed} = errm_router:dispatch(Routes, Req).

%% ── errm_response:build/3 ──────────────────────────────────────────

response_build_test() ->
    Bin = errm_response:build(200, #{~"content-type" => ~"text/plain"}, ~"OK"),
    ?assertNotEqual(nomatch, binary:match(Bin, ~"HTTP/1.1 200 OK\r\n")),
    ?assertNotEqual(nomatch, binary:match(Bin, ~"content-type: text/plain\r\n")).

response_adds_content_length_test() ->
    Bin = errm_response:build(200, #{~"x-foo" => ~"bar"}, ~"hello"),
    ?assertNotEqual(nomatch, binary:match(Bin, ~"content-length: 5\r\n")).

%% ── errm_middleware:run/3 ──────────────────────────────────────────

middleware_passthrough_test() ->
    %% No middleware — handler runs directly
    Result = errm_middleware:run([], #{method => get, path => [], raw_path => ~"/", params => #{}, peer => {{0,0,0,0}, 0}, headers => #{}, body => <<>>}, fun() -> {ok, {200, #{}, ~"ok"}} end),
    ?assertEqual({ok, {200, #{}, ~"ok"}}, Result).

middleware_adds_header_test() ->
    AddHeader = fun(_Req, Next) ->
        case Next() of
            {ok, {Status, H, Body}} ->
                {ok, {Status, H#{~"x-middleware" => ~"yes"}, Body}};
            Other -> Other
        end
    end,
    Result = errm_middleware:run([AddHeader], #{method => get, path => [], raw_path => ~"/", params => #{}, peer => {{0,0,0,0}, 0}, headers => #{}, body => <<>>},
        fun() -> {ok, {200, #{}, ~"body"}} end),
    ?assertMatch({ok, {200, #{~"x-middleware" := ~"yes"}, ~"body"}}, Result).

%% ── errm_cors:make/1 ───────────────────────────────────────────────

cors_simple_request_test() ->
    CORS = errm_cors:make(#{origins => ~"*", credentials => true, methods => [get, post], max_age => 86400, exposed_headers => [], headers => [] }),
    Req = #{method => get, path => [~"test"], raw_path => ~"/test",
            headers => #{~"origin" => ~"https://example.com"},
            body => <<>>, params => #{}, peer => {{127,0,0,1},12345}},
    Next = fun() -> {ok, {200, #{~"x-foo" => ~"bar"}, ~"body"}} end,
    {ok, {200, Headers, ~"body"}} = CORS(Req, Next),
    ?assertEqual(~"*", maps:get(~"access-control-allow-origin", Headers)),
    ?assertEqual(~"Origin", maps:get(~"vary", Headers)).

cors_preflight_test() ->
    CORS = errm_cors:make(#{origins => ~"*", credentials => true, methods => [get, post], max_age => 86400, exposed_headers => [], headers => []}),
    Req = #{method => options, path => [~"test"], raw_path => ~"/test",
            headers => #{~"origin" => ~"https://example.com",
                        ~"access-control-request-headers" => ~"Content-Type"},
            body => <<>>, params => #{}, peer => {{127,0,0,1},12345}},
    {ok, {204, Headers, <<>>}} = CORS(Req, fun() -> {error, should_not_reach} end),
    ?assertEqual(~"*", maps:get(~"access-control-allow-origin", Headers)),
    ?assert(maps:is_key(~"access-control-allow-methods", Headers)).

cors_origin_denied_test() ->
    CORS = errm_cors:make(#{origins => [~"https://trusted.com"], credentials => true, methods => [get, post], max_age => 86400, exposed_headers => [], headers => []}),
    Req = #{method => get, path => [~"test"], raw_path => ~"/test",
            headers => #{~"origin" => ~"https://evil.com"},
            body => <<>>, params => #{}, peer => {{127,0,0,1},12345}},
    {ok, {200, Headers, _}} = CORS(Req, fun() -> {ok, {200, #{}, ~"body"}} end),
    ?assertNot(maps:is_key(~"access-control-allow-origin", Headers)).
