-module(errm_http_request).
-export([parse/1]).
-include("include/errm_http.hrl").

-define(CRLF, ~"\r\n").
-define(CRLF_CRLF, ~"\r\n\r\n").
-define(SP, ~" ").

-spec parse(binary()) -> {ok, request(), binary()} | {partial, binary()} | {error, atom()}.
parse(Data) ->
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
          CL = maps:get(~"content-length", Headers, ~"0"),
          case binary_to_integer(CL) of
            N when N =< byte_size(Body) ->
              Max = persistent_term:get({errm_http, max_body_size}, 10_485_760),
              case N > Max of
                true ->
                  {error, request_entity_too_large};
                false->
                  <<ActualBody:N/binary, Rest/binary>> = Body,
                  Req = #{
                    method   => Method,
                    raw_path => RawPath,
                    path     => path_segments(RawPath),
                    query    => Query,
                    headers  => Headers,
                    body     => ActualBody,
                    params   => #{},
                    peer     => undefined
                  },
                  {ok, Req, Rest}
              end;
            _NeedMore ->
              {partial, Data}
          end;
        {error, Reason} ->
          {error, Reason}
      end;
    [_NoCRLFCRLF] ->
      {partial, Data}
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
