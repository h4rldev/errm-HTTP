-module(errm_http_request).
-export([parse/1]).
-include("include/errm_http.hrl").

-define(CRLF, ~"\r\n").
-define(CRLF_CRLF, ~"\r\n\r\n").
-define(SP, ~" ").
-define(MAX_HEADER_BYTES, 65536).

-on_load(init_patterns/0).

init_patterns() ->
  Pats = #{
    crlf       => binary:compile_pattern(?CRLF),
    crlf_crlf  => binary:compile_pattern(?CRLF_CRLF),
    sp         => binary:compile_pattern(?SP),
    colon      => binary:compile_pattern(~":"),
    amp        => binary:compile_pattern(~"&"),
    eq         => binary:compile_pattern(~"="),
    qmark      => binary:compile_pattern(~"?"),
    slash      => binary:compile_pattern(~"/"),
    semicolon  => binary:compile_pattern(~";")
  },
  persistent_term:put({errm_http_request, patterns}, Pats),
  ok.

pat(Key) ->
  case get('$errm_patterns') of
    undefined ->
      Pats = persistent_term:get({errm_http_request, patterns}),
      put('$errm_patterns', Pats),
      maps:get(Key, Pats);
    Pats ->
      maps:get(Key, Pats)
  end.

-spec parse(binary()) -> {ok, request(), binary()} | {partial, binary()} | {error, atom()}.
parse(Data) ->
  case binary:match(Data, pat(crlf_crlf)) of
    nomatch when byte_size(Data) > ?MAX_HEADER_BYTES ->
      {error, request_entity_too_large};
    _ ->
      parse_one(Data)
  end.

parse_one(Data) ->
  case split_request_line(Data) of
    {ok, ReqLine, Rest} ->
      case parse_method_path(ReqLine) of
        {ok, Method, RawPath, Query} ->
          parse_headers_body(Rest, Method, RawPath, Query);
        error ->
          {error, bad_request_line}
        end;
    incomplete ->
      {partial, Data};
    error ->
      {error, bad_request}
  end.

split_request_line(Data) ->
  case binary:split(Data, pat(crlf)) of
    [ReqLine, Rest] when byte_size(ReqLine) > 0 ->
      {ok, ReqLine, Rest};
    [_] -> incomplete;
    _ -> error
  end.

parse_method_path(Data) ->
  Parts = binary:split(Data, pat(sp), [global]),
  case Parts of
    [MethodBin, <<"/", _/binary>> = Target, <<"HTTP/1.", _/binary>>] ->
      case method_from_binary(MethodBin) of
        {ok, Method} ->
          {RawPath, Query} = split_query(Target),
          {ok, Method, RawPath, Query};
        error -> error
      end;
    _ -> error
  end.

split_query(Target) ->
  case binary:split(Target, pat(qmark)) of
    [Path] -> {Path, #{}};
    [Path, QueryBin] -> {Path, parse_query(QueryBin)}
  end.

parse_query(<<>>) -> #{};
parse_query(Bin) ->
  Pairs = binary:split(Bin, pat(amp), [global]),
  maps:from_list([begin
    case binary:split(KV, pat(eq)) of
      [K, V] -> {K, V};
      [K] -> {K, <<>>}
    end
  end || KV <- Pairs]).

method_from_binary(~"GET")     -> {ok, get};
method_from_binary(~"POST")    -> {ok, post};
method_from_binary(~"PUT")     -> {ok, put};
method_from_binary(~"DELETE")  -> {ok, delete};
method_from_binary(~"PATCH")   -> {ok, patch};
method_from_binary(~"OPTIONS") -> {ok, options};
method_from_binary(~"HEAD")    -> {ok, head};
method_from_binary(Method) when byte_size(Method) =< 7 ->
  case string:uppercase(Method) of
    ~"GET"     -> {ok, get};
    ~"POST"    -> {ok, post};
    ~"PUT"     -> {ok, put};
    ~"DELETE"  -> {ok, delete};
    ~"PATCH"   -> {ok, patch};
    ~"OPTIONS" -> {ok, options};
    ~"HEAD"    -> {ok, head};
    _          -> error
  end;
method_from_binary(_) -> error.

parse_headers_body(Data, Method, RawPath, Query) ->
  case binary:split(Data, pat(crlf_crlf)) of
    [HeaderBlock, Body] ->
      RawHeaders = binary:split(HeaderBlock, pat(crlf), [global]),
      case parse_headers(RawHeaders, #{}) of
        {ok, Headers} ->
          Max = persistent_term:get({errm_http, max_body_size}, 10_485_760),
          case body_framing(Headers) of
            chunked ->
              case decode_chunked(Body, Max) of
                {ok, ActualBody, Rest} ->
                  {ok, build_request(Method, RawPath, Query, Headers, ActualBody), Rest};
                more ->
                  {partial, Data};
                {error, Reason} ->
                  {error, Reason}
              end;
            {content_length, N} when N > byte_size(Body) ->
              {partial, Data};
            {content_length, N} when N > Max ->
              {error, request_entity_too_large};
            {content_length, N} ->
              <<ActualBody:N/binary, Rest/binary>> = Body,
              {ok, build_request(Method, RawPath, Query, Headers, ActualBody), Rest};
            error ->
              {error, bad_request}
          end;
        {error, Reason} ->
          {error, Reason}
      end;
    [_NoCRLFCRLF] ->
      {partial, Data}
  end.

body_framing(Headers) ->
  case maps:get(~"transfer-encoding", Headers, undefined) of
    undefined ->
      case parse_content_length(maps:get(~"content-length", Headers, ~"0")) of
        {ok, N} -> {content_length, N};
        error -> error
      end;
    TransferEncoding ->
      case binary:match(ascii_lower(TransferEncoding), ~"chunked") of
        nomatch -> error;
        _ -> chunked
      end
  end.

build_request(Method, RawPath, Query, Headers, Body) ->
  #{
    method   => Method,
    raw_path => RawPath,
    path     => path_segments(RawPath),
    query    => Query,
    headers  => Headers,
    body     => Body,
    params   => #{},
    peer     => undefined
  }.

decode_chunked(Data, Max) ->
  decode_chunked(Data, [], 0, Max).

decode_chunked(Data, Acc, Size, Max) ->
  case binary:split(Data, pat(crlf)) of
    [SizeLine, Rest] ->
      case parse_chunk_size(SizeLine) of
        {ok, 0} ->
          case skip_trailers(Rest) of
            {ok, Rest2} -> {ok, iolist_to_binary(lists:reverse(Acc)), Rest2};
            more -> more
          end;
        {ok, N} when Size + N > Max ->
          {error, request_entity_too_large};
        {ok, N} when N =< byte_size(Rest) ->
          <<Chunk:N/binary, After/binary>> = Rest,
          case After of
            <<13, 10, Rest2/binary>> ->
              decode_chunked(Rest2, [Chunk | Acc], Size + N, Max);
            _ when byte_size(After) < 2 ->
              more;
            _ ->
              {error, bad_request}
          end;
        {ok, _N} ->
          more;
        error ->
          {error, bad_request}
      end;
    [_] ->
      more
  end.

parse_chunk_size(Line) ->
  SizePart = hd(binary:split(Line, pat(semicolon))),
  try binary_to_integer(trim(SizePart), 16) of
    N when N >= 0 -> {ok, N};
    _ -> error
  catch _:_ -> error
  end.

skip_trailers(<<13, 10, Rest/binary>>) -> {ok, Rest};
skip_trailers(Bin) ->
  case binary:match(Bin, pat(crlf)) of
    nomatch -> more;
    {Pos, _} ->
      <<_Trailer:Pos/binary, 13, 10, Rest/binary>> = Bin,
      skip_trailers(Rest)
  end.

parse_headers([~""], Acc) -> {ok, Acc};
parse_headers([Line | Rest], Acc) -> 
  case binary:split(Line, pat(colon)) of
    [Name, Value] ->
      Name2 = trim_lower(Name),
      Val2 = trim(Value),
      parse_headers(Rest, Acc#{Name2 => Val2});
    _ ->
      {error, bad_header}
  end;
parse_headers([], Acc) -> {ok, Acc}.

parse_content_length(Bin) ->
  try binary_to_integer(Bin) of
    N when N >= 0 -> {ok, N};
    _ -> error
  catch _:_ -> error
  end.

path_segments(~"/") -> [];
path_segments(<<"/", Path/binary>>) ->
  Path2 = case binary:last(Path) of
    $/ -> binary:part(Path, 0, byte_size(Path) - 1);
    _ -> Path
  end,
  binary:split(Path2, pat(slash), [global]);
path_segments(Path) ->
  binary:split(Path, pat(slash), [global]).

trim(Bin) -> ascii_trim(Bin).

trim_lower(Bin) -> ascii_lower(ascii_trim(Bin)).

ascii_trim(Bin) ->
  case is_ascii(Bin) of
    false -> string:trim(Bin);
    true -> ascii_trim_loop(Bin)
  end.

ascii_trim_loop(Bin) ->
  Size = byte_size(Bin),
  case trim_left(Bin, 0, Size) of
    Pos when Pos >= Size -> <<>>;
    Pos -> trim_right(Bin, Pos, Size)
  end.

trim_left(<<C, Rest/binary>>, Pos, Size)
    when C =:= $\s; C =:= $\t; C =:= $\n; C =:= $\r; C =:= $\v; C =:= $\f ->
  trim_left(Rest, Pos + 1, Size);
trim_left(_Bin, Pos, _Size) -> Pos.

trim_right(Bin, Pos, Size) ->
  Last = last_non_ws(Bin, Size - 1, Pos),
  binary:part(Bin, Pos, Last - Pos + 1).

last_non_ws(Bin, Idx, Pos) when Idx >= Pos ->
  case binary:at(Bin, Idx) of
    C when C =:= $\s; C =:= $\t; C =:= $\n; C =:= $\r; C =:= $\v; C =:= $\f ->
      last_non_ws(Bin, Idx - 1, Pos);
    _ -> Idx
  end;
last_non_ws(_Bin, Idx, _Pos) -> Idx.

ascii_lower(Bin) ->
  case has_upper(Bin) of
    true -> ascii_lower_loop(Bin, []);
    false -> Bin
  end.

ascii_lower_loop(<<C, Rest/binary>>, Acc) when C >= $A, C =< $Z ->
  ascii_lower_loop(Rest, [C + 32 | Acc]);
ascii_lower_loop(<<C, Rest/binary>>, Acc) ->
  ascii_lower_loop(Rest, [C | Acc]);
ascii_lower_loop(<<>>, Acc) ->
  list_to_binary(lists:reverse(Acc)).

has_upper(<<C, _/binary>>) when C >= $A, C =< $Z -> true;
has_upper(<<_, Rest/binary>>) -> has_upper(Rest);
has_upper(<<>>) -> false.

is_ascii(<<C, _/binary>>) when C >= 128 -> false;
is_ascii(<<_, Rest/binary>>) -> is_ascii(Rest);
is_ascii(<<>>) -> true.
