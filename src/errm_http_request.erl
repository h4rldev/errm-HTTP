-module(errm_http_request).
-export([parse/1]).
-include("include/errm_http.hrl").

-define(CRLF, ~"\r\n").
-define(CRLF_CRLF, ~"\r\n\r\n").
-define(SP, ~" ").
-define(MAX_HEADER_BYTES, 65536).

-spec parse(binary()) -> {ok, request(), binary()} | {partial, binary()} | {error, atom()}.
parse(Data) ->
  case binary:match(Data, ?CRLF_CRLF) of
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
  case binary:split(Data, ?CRLF) of
    [ReqLine, Rest] when byte_size(ReqLine) > 0 ->
      {ok, ReqLine, Rest};
    [_] -> incomplete;
    _ -> error
  end.

parse_method_path(Data) ->
  Parts = binary:split(Data, ?SP, [global]),
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
  case binary:split(Target, <<"?">>) of
    [Path] -> {Path, #{}};
    [Path, QueryBin] -> {Path, parse_query(QueryBin)}
  end.

parse_query(<<>>) -> #{};
parse_query(Bin) ->
  Pairs = binary:split(Bin, <<"&">>, [global]),
  maps:from_list([begin
    case binary:split(KV, <<"=">>) of
      [K, V] -> {K, V};
      [K] -> {K, <<>>}
    end
  end || KV <- Pairs]).

method_from_binary(Method) ->
 case string:uppercase(Method) of
   ~"GET"     -> {ok, get};
   ~"POST"    -> {ok, post};
   ~"PUT"     -> {ok, put};
   ~"DELETE"  -> {ok, delete};
   ~"PATCH"   -> {ok, patch};
   ~"OPTIONS" -> {ok, options};
   ~"HEAD"    -> {ok, head};
   _          -> error
 end.

parse_headers_body(Data, Method, RawPath, Query) ->
  case binary:split(Data, [?CRLF_CRLF]) of
    [HeaderBlock, Body] ->
      RawHeaders = binary:split(HeaderBlock, ?CRLF, [global]),
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
      case binary:match(string:lowercase(TransferEncoding), ~"chunked") of
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
  case binary:split(Data, ?CRLF) of
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
  SizePart = hd(binary:split(Line, ~";")),
  try binary_to_integer(string:trim(SizePart), 16) of
    N when N >= 0 -> {ok, N};
    _ -> error
  catch _:_ -> error
  end.

skip_trailers(<<13, 10, Rest/binary>>) -> {ok, Rest};
skip_trailers(Bin) ->
  case binary:match(Bin, ?CRLF) of
    nomatch -> more;
    {Pos, _} ->
      <<_Trailer:Pos/binary, 13, 10, Rest/binary>> = Bin,
      skip_trailers(Rest)
  end.

parse_headers([~""], Acc) -> {ok, Acc};
parse_headers([Line | Rest], Acc) -> 
  case binary:split(Line, ~":") of
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
  binary:split(Path2, ~"/", [global]);
path_segments(Path) ->
  binary:split(Path, ~"/", [global]).

trim(Bin) ->
  string:trim(Bin).

trim_lower(Bin) ->
  string:lowercase(string:trim(Bin)).
