-module(errm_response).
-export([build/3, build_headers/3, encode_chunk/1, final_chunk/0]).
-include("errm.hrl").

-define(CRLF, ~"\r\n").

-ifndef(ERRM_CHUNK_THRESHOLD).
-define(ERRM_CHUNK_THRESHOLD, 8192).
-endif.

status_codes() -> #{
        100 => ~"Continue",
        101 => ~"Switching Protocols",
        103 => ~"Early Hints",
        200 => ~"OK",
        201 => ~"Created",
        202 => ~"Accepted",
        203 => ~"Non-Authoritative Information",
        204 => ~"No Content",
        205 => ~"Reset Content",
        206 => ~"Partial Content",
        300 => ~"Multiple Choices",
        301 => ~"Moved Permanently",
        302 => ~"Found",
        303 => ~"See Other",
        304 => ~"Not Modified",
        307 => ~"Temporary Redirect",
        308 => ~"Permanent Redirect",
        400 => ~"Bad Request",
        401 => ~"Unauthorized",
        402 => ~"Payment Required",
        403 => ~"Forbidden",
        404 => ~"Not Found",
        405 => ~"Method Not Allowed",
        406 => ~"Not Acceptable",
        407 => ~"Proxy Authentication Required",
        408 => ~"Request Timeout",
        409 => ~"Conflict",
        410 => ~"Gone",
        411 => ~"Length Required",
        412 => ~"Precondition Failed",
        413 => ~"Content Too Large",
        414 => ~"URI Too Long",
        415 => ~"Unsupported Media Type",
        416 => ~"Range Not Satisfiable",
        417 => ~"Expectation Failed",
        418 => ~"I'm a teapot",
        421 => ~"Misdirected Request",
        422 => ~"Unprocessable Content",
        423 => ~"Locked",
        424 => ~"Failed Dependency",
        425 => ~"Too Early",
        426 => ~"Upgrade Required",
        428 => ~"Precondition Required",
        429 => ~"Too Many Requests",
        431 => ~"Request Header Fields Too Large",
        451 => ~"Unavailable For Legal Reasons",
        500 => ~"Internal Server Error",
        501 => ~"Not Implemented",
        502 => ~"Bad Gateway",
        503 => ~"Service Unavailable",
        504 => ~"Gateway Timeout",
        505 => ~"HTTP Version Not Supported",
        506 => ~"Variant Also Negotiates",
        507 => ~"Insufficient Storage",
        508 => ~"Loop Detected",
        510 => ~"Not Extended",
        511 => ~"Network Authentication Required"
    }.


-spec build(pos_integer(), headers(), iodata()) -> binary().
build(Status, Headers, Body) ->
  Normalized = normalize_headers(Headers),
  StatusLine = status_line(Status),
  Headers2 = header_lines(Normalized, Body),
  iolist_to_binary([StatusLine, ?CRLF, Headers2, ?CRLF, Body]).

-spec build_headers(pos_integer(), headers(), non_neg_integer()) -> binary().
build_headers(Status, Headers, BodySize) ->
  Normalized = normalize_headers(Headers),
  StatusLine = status_line(Status),
  Hdrs = case should_chunk(Normalized, BodySize) of
    true  -> Normalized#{~"transfer-encoding" => ~"chunked"};
    false -> add_content_length(Normalized, BodySize)
  end,
  iolist_to_binary([StatusLine, ?CRLF, header_lines(Hdrs, <<>>), ?CRLF]).

-spec encode_chunk(binary()) -> iolist().
encode_chunk(Data) ->
  Size = byte_size(Data),
  Hex = integer_to_list(Size, 16),
  [Hex, ?CRLF, Data, ?CRLF].

-spec final_chunk() -> binary().
final_chunk() ->
  ~"0\r\n\r\n".


-spec status_line(pos_integer()) -> iolist().
status_line(Status) ->
  Phrase = maps:get(Status, status_codes(), ~"Unknown"),
  io_lib:format("HTTP/1.1 ~B ~s", [Status, Phrase]).

should_chunk(Headers, BodySize) ->
  not maps:is_key(~"transfer-encoding", Headers)
  andalso not maps:is_key(~"content-length", Headers)
  andalso BodySize >= ?ERRM_CHUNK_THRESHOLD.

add_content_length(Headers, BodySize) ->
  Headers#{~"content-length" => integer_to_binary(BodySize)}.

normalize_headers(Headers) ->
  maps:fold(fun(K, V, Acc) ->
    Acc#{string:lowercase(to_binary(K)) => to_binary(V)}
  end, #{}, Headers).

to_binary(S) when is_list(S) -> list_to_binary(S);
to_binary(S) -> S.

header_lines(Headers, Body) ->
  HasTE = maps:is_key(~"transfer-encoding", Headers),
  HasCL = maps:is_key(~"content-length", Headers),
  Headers2 = case {HasTE, HasCL} of
    {true, _} -> Headers;
    {_, true} -> Headers;
    {false, false} -> Headers#{~"content-length" => integer_to_binary(iolist_size(Body))}
  end,
  maps:fold(fun(K, V, Acc) ->
    [[K , ~": ", V, ?CRLF] | Acc]
  end, [], Headers2).
