-module(errm_http_response).
-export([build/3, build_headers/3, build_chunked_headers/2, encode_chunk/1, final_chunk/0]).
-include("include/errm_http.hrl").

-define(CRLF, ~"\r\n").

-define(STATUS_LINES, #{
  100 => <<"HTTP/1.1 100 Continue\r\n">>,
  101 => <<"HTTP/1.1 101 Switching Protocols\r\n">>,
  103 => <<"HTTP/1.1 103 Early Hints\r\n">>,
  200 => <<"HTTP/1.1 200 OK\r\n">>,
  201 => <<"HTTP/1.1 201 Created\r\n">>,
  202 => <<"HTTP/1.1 202 Accepted\r\n">>,
  203 => <<"HTTP/1.1 203 Non-Authoritative Information\r\n">>,
  204 => <<"HTTP/1.1 204 No Content\r\n">>,
  205 => <<"HTTP/1.1 205 Reset Content\r\n">>,
  206 => <<"HTTP/1.1 206 Partial Content\r\n">>,
  300 => <<"HTTP/1.1 300 Multiple Choices\r\n">>,
  301 => <<"HTTP/1.1 301 Moved Permanently\r\n">>,
  302 => <<"HTTP/1.1 302 Found\r\n">>,
  303 => <<"HTTP/1.1 303 See Other\r\n">>,
  304 => <<"HTTP/1.1 304 Not Modified\r\n">>,
  307 => <<"HTTP/1.1 307 Temporary Redirect\r\n">>,
  308 => <<"HTTP/1.1 308 Permanent Redirect\r\n">>,
  400 => <<"HTTP/1.1 400 Bad Request\r\n">>,
  401 => <<"HTTP/1.1 401 Unauthorized\r\n">>,
  402 => <<"HTTP/1.1 402 Payment Required\r\n">>,
  403 => <<"HTTP/1.1 403 Forbidden\r\n">>,
  404 => <<"HTTP/1.1 404 Not Found\r\n">>,
  405 => <<"HTTP/1.1 405 Method Not Allowed\r\n">>,
  406 => <<"HTTP/1.1 406 Not Acceptable\r\n">>,
  407 => <<"HTTP/1.1 407 Proxy Authentication Required\r\n">>,
  408 => <<"HTTP/1.1 408 Request Timeout\r\n">>,
  409 => <<"HTTP/1.1 409 Conflict\r\n">>,
  410 => <<"HTTP/1.1 410 Gone\r\n">>,
  411 => <<"HTTP/1.1 411 Length Required\r\n">>,
  412 => <<"HTTP/1.1 412 Precondition Failed\r\n">>,
  413 => <<"HTTP/1.1 413 Content Too Large\r\n">>,
  414 => <<"HTTP/1.1 414 URI Too Long\r\n">>,
  415 => <<"HTTP/1.1 415 Unsupported Media Type\r\n">>,
  416 => <<"HTTP/1.1 416 Range Not Satisfiable\r\n">>,
  417 => <<"HTTP/1.1 417 Expectation Failed\r\n">>,
  418 => <<"HTTP/1.1 418 I'm a teapot\r\n">>,
  421 => <<"HTTP/1.1 421 Misdirected Request\r\n">>,
  422 => <<"HTTP/1.1 422 Unprocessable Content\r\n">>,
  423 => <<"HTTP/1.1 423 Locked\r\n">>,
  424 => <<"HTTP/1.1 424 Failed Dependency\r\n">>,
  425 => <<"HTTP/1.1 425 Too Early\r\n">>,
  426 => <<"HTTP/1.1 426 Upgrade Required\r\n">>,
  428 => <<"HTTP/1.1 428 Precondition Required\r\n">>,
  429 => <<"HTTP/1.1 429 Too Many Requests\r\n">>,
  431 => <<"HTTP/1.1 431 Request Header Fields Too Large\r\n">>,
  451 => <<"HTTP/1.1 451 Unavailable For Legal Reasons\r\n">>,
  500 => <<"HTTP/1.1 500 Internal Server Error\r\n">>,
  501 => <<"HTTP/1.1 501 Not Implemented\r\n">>,
  502 => <<"HTTP/1.1 502 Bad Gateway\r\n">>,
  503 => <<"HTTP/1.1 503 Service Unavailable\r\n">>,
  504 => <<"HTTP/1.1 504 Gateway Timeout\r\n">>,
  505 => <<"HTTP/1.1 505 HTTP Version Not Supported\r\n">>,
  506 => <<"HTTP/1.1 506 Variant Also Negotiates\r\n">>,
  507 => <<"HTTP/1.1 507 Insufficient Storage\r\n">>,
  508 => <<"HTTP/1.1 508 Loop Detected\r\n">>,
  510 => <<"HTTP/1.1 510 Not Extended\r\n">>,
  511 => <<"HTTP/1.1 511 Network Authentication Required\r\n">>
}).


-spec build(pos_integer(), headers(), iodata()) -> binary().
build(Status, Headers, Body) ->
  Normalized = ensure_normalized(Headers),
  Headers2 = case {maps:is_key(~"transfer-encoding", Normalized), maps:is_key(~"content-length", Normalized)} of
    {true, _} -> Normalized;
    {_, true} -> Normalized;
    {false, false} -> Normalized#{~"content-length" => integer_to_binary(iolist_size(Body))}
  end,
  iolist_to_binary([status_line(Status), header_lines(Headers2), ?CRLF, Body]).


-spec build_headers(pos_integer(), headers(), non_neg_integer()) -> iodata().
build_headers(Status, Headers, BodySize) ->
  Hdrs = add_content_length(ensure_normalized(Headers), BodySize),
  [status_line(Status), header_lines(Hdrs), ?CRLF].


-spec build_chunked_headers(pos_integer(), headers()) -> iodata().
build_chunked_headers(Status, Headers) ->
  Hdrs = ensure_normalized(Headers),
  [status_line(Status), header_lines(Hdrs#{~"transfer-encoding" => ~"chunked"}), ?CRLF].


-spec encode_chunk(binary()) -> iolist().
encode_chunk(Data) ->
  Size = byte_size(Data),
  Hex = integer_to_list(Size, 16),
  [Hex, ?CRLF, Data, ?CRLF].


-spec final_chunk() -> binary().
final_chunk() ->
  ~"0\r\n\r\n".


-spec status_line(pos_integer()) -> binary().
status_line(Status) ->
    maps:get(Status, ?STATUS_LINES, <<"HTTP/1.1 500 Unknown\r\n">>).


add_content_length(Headers, BodySize) ->
  Headers#{~"content-length" => integer_to_binary(BodySize)}.


ensure_normalized(Headers) ->
  case maps:fold(fun(K, _V, Acc) -> Acc andalso is_lower_binary(K) end, true, Headers) of
    true -> Headers;
    false -> normalize_headers(Headers)
  end.


is_lower_binary(K) when is_binary(K) -> not has_upper(K);
is_lower_binary(_) -> false.


normalize_headers(Headers) ->
  maps:fold(fun(K, V, Acc) ->
    Acc#{normalize_key(K) => to_binary(V)}
  end, #{}, Headers).


normalize_key(K) when is_binary(K) ->
  case has_upper(K) of
    true  -> string:lowercase(K);
    false -> K
  end;
normalize_key(K) -> string:lowercase(to_binary(K)).

has_upper(<<C, _/binary>>) when C >= $A, C =< $Z -> true;
has_upper(<<_, Rest/binary>>) -> has_upper(Rest);
has_upper(<<>>) -> false.


to_binary(S) when is_list(S) -> list_to_binary(S);
to_binary(S) -> S.


header_lines(Headers) ->
  maps:fold(fun(K, V, Acc) ->
    [[K , ~": ", V, ?CRLF] | Acc]
  end, [], Headers).
