-module(errm_http_compress).
-export([compress/0, compress/1]).
-export([decompress/0, decompress/1]).
-export([available_encodings/0]).
-include("include/errm_http.hrl").
-export_type([compress_opts/0]).

-spec compress() -> CompressionMiddleware :: middleware().
compress() -> compress(#{}).

-spec compress(CompressionOptions :: compress_opts()) -> CompressionMiddleware :: middleware().
compress(CompressionOptions) ->
  Preferred = maps:get(preferred, CompressionOptions, [gzip, deflate, zstd, brotli]),
  MinLength = maps:get(min_length, CompressionOptions, 1024),
  Level = maps:get(compression_level, CompressionOptions, 6),

  fun(Req, Next) ->
    case Next(Req) of
      {ok, {Status, Headers, Body}} ->
        case should_compress(Req, Headers, Body, MinLength) of
          true ->
            case select_encoding(Req, Preferred) of
              {ok, Enc} ->
                io:format("Compressing with: ~p~n", [Enc]),
                compress_response(Enc, Status, Headers, Body, Level);
              error ->
                io:format("No compression selected~n"),
                {ok, {Status, Headers, Body}}
              end;
          false ->
            {ok, {Status, Headers, Body}}
        end;
      Other -> Other
    end
  end.

-spec decompress() -> DecompressionMiddleware :: middleware().
decompress() -> decompress(#{}).

-spec decompress(DecompressionOptions :: decompress_opts()) -> DecompressionMiddleware :: middleware().
decompress(DecompressionOptions) ->
  Allowed = maps:get(allowed, DecompressionOptions, available_encodings()),
  fun(Req, Next) ->
      case maps:get(<<"content-encoding">>, maps:get(headers, Req), undefined) of
        undefined -> Next(Req);
        Enc ->
          Encoding = encoding_atom(Enc),
          case lists:member(Encoding, Allowed) of
            true ->
              case decompress_body(Encoding, maps:get(body, Req)) of
                {ok, Body} ->
                  Req1 = Req#{body => Body, headers => maps:remove(<<"content-encoding">>, maps:get(headers, Req))},
                  Next(Req1);
                error ->
                  {error, bad_request}
              end;
            false ->
              Next(Req)
          end
      end
  end.


should_compress(Req, Headers, Body, MinLength) ->
    Size = iolist_size(Body),
    Accept = maps:get(<<"accept-encoding">>, maps:get(headers, Req), <<>>),
    ClientEncodings = parse_accept_encoding(Accept),
    Available = available_encodings(),
    Supported = [E || E <- ClientEncodings, lists:member(E, Available)],
    Size >= MinLength
    andalso not maps:is_key(<<"content-encoding">>, Headers)
    andalso not maps:is_key(<<"transfer-encoding">>, Headers)
    andalso Supported =/= [].


select_encoding(Req, Preferred) ->
    Accept = maps:get(<<"accept-encoding">>, maps:get(headers, Req), <<>>),
    ClientEncodings = parse_accept_encoding(Accept),
    Available = available_encodings(),
    Supported = [E || E <- ClientEncodings, lists:member(E, Available)],
    find_first(fun(E) -> lists:member(E, Supported) end, Preferred).



parse_accept_encoding(<<>>) -> [];
parse_accept_encoding(Header) ->
    Tokens = binary:split(Header, <<",">>, [global]),
    [begin
        Clean = string:trim(Token),
        encoding_atom(string:lowercase(Clean))
    end || Token <- Tokens].



encoding_atom(<<"gzip">>) -> gzip;
encoding_atom(<<"deflate">>) -> deflate;
encoding_atom(<<"zstd">>) -> zstd;
encoding_atom(<<"br">>) -> brotli;
encoding_atom(<<"*">>) -> '*';
encoding_atom(_) -> undefined.


find_first(_Pred, []) -> error;
find_first(Pred, [H|T]) ->
  case Pred(H) of
    true -> {ok, H};
    false -> find_first(Pred, T)
  end.


-spec available_encodings() -> [encoding()].
available_encodings() ->
    [E || E <- [gzip, deflate, zstd, brotli], is_available(E)].
is_available(gzip) -> true;
is_available(deflate) -> true;
is_available(zstd) -> code:ensure_loaded(errm_http_zstd_nif) =:= {module, errm_http_zstd_nif};
is_available(brotli) -> code:ensure_loaded(errm_http_brotli_nif) =:= {module, errm_http_brotli_nif}.


compress_response(undefined, Status, Headers, Body, _Level) ->
  {ok, {Status, Headers, Body}};
compress_response(Encoding, Status, Headers, Body, Level) ->
  case compress_body(Encoding, Body, Level) of
    {ok, Compressed} ->
      NewHeaders = Headers#{
        <<"content-encoding">> => encoding_name(Encoding),
        <<"vary">> => maybe_add_vary(Headers)
      },
      NewHeaders1 = maps:remove(<<"content-length">>, NewHeaders),
      {ok, {Status, NewHeaders1, Compressed}};
    error ->
      {ok, {Status, Headers, Body}}
  end.


maybe_add_vary(Headers) ->
  case maps:get(<<"vary">>, Headers, undefined) of
    undefined -> <<"Accept-Encoding">>;
    Existing -> <<Existing/binary, ", Accept-Encoding">>
  end.


encoding_name(gzip) -> <<"gzip">>;
encoding_name(deflate) -> <<"deflate">>;
encoding_name(zstd) -> <<"zstd">>;
encoding_name(brotli) -> <<"br">>.

compress_body(gzip, Data, Level) ->
  Mapped = map_level(gzip, Level),
  try
    Z = zlib:open(),
    ok = zlib:deflateInit(Z, Mapped, deflated, 31, 8, default),
    Compressed = zlib:deflate(Z, Data, finish),
    ok = zlib:deflateEnd(Z),
    {ok, Compressed}
  catch _:_ -> error
  end;
compress_body(deflate, Data, Level) ->
  Mapped = map_level(deflate, Level),
  try
    Z = zlib:open(),
    ok = zlib:deflateInit(Z, Mapped, deflated, 15, 8, default),
    Compressed = zlib:deflate(Z, Data, finish),
    ok = zlib:deflateEnd(Z),
    {ok, Compressed}
  catch _:_ -> error
  end;
compress_body(zstd, Data, Level) ->
  Mapped = map_level(zstd, Level),
  try errm_http_zstd_nif:compress(Data, Mapped) of
    {ok, Compressed} -> {ok, Compressed}
  catch _:_ -> error
  end;
compress_body(brotli, Data, Level) ->
  Mapped = map_level(brotli, Level),
  try errm_http_brotli_nif:compress(Data, Mapped) of
    {ok, Compressed} -> {ok, Compressed}
  catch _:_ -> error
  end.

decompress_body(gzip, Data) ->
  try
    Z = zlib:open(),
    ok = zlib:inflateInit(Z, 31),
    Decompressed = zlib:inflate(Z, Data),
    ok = zlib:inflateEnd(Z),
    {ok, Decompressed}
  catch _:_ -> error
  end;
decompress_body(deflate, Data) ->
  try
    Z = zlib:open(),
    ok = zlib:inflateInit(Z, 15),
    Decompressed = zlib:inflate(Z, Data),
    ok = zlib:inflateEnd(Z),
    {ok, Decompressed}
  catch _:_ -> error
  end;
decompress_body(zstd, Data) ->
  try errm_http_zstd_nif:decompress(Data) of
    {ok, Decompressed} -> {ok, Decompressed}
  catch _:_ -> error
  end;
decompress_body(brotli, Data) ->
  try errm_http_brotli_nif:decompress(Data) of
    {ok, Decompressed} -> {ok, Decompressed}
  catch _:_ -> error
  end.

map_level(gzip, Level) -> clamp(Level, 0, 9);
map_level(deflate, Level) -> clamp(Level, 0, 9);
map_level(zstd, Level) ->
    %% zstd: 1..22 (or 0 = default). Map 0..9 to 1..22.
    %% Simple mapping: Level * 2 + 1  →  0→1, 1→3, ..., 9→19
    %% But allow up to 22, so we cap.
    Min = 1,
    Max = 22,
    Mapped = Level * 2 + 1,
    clamp(Mapped, Min, Max);
map_level(brotli, Level) ->
    %% brotli: 0..11. Map 0..9 to 0..11.
    Min = 0,
    Max = 11,
    Mapped = (Level * 11) div 9,   %% integer division
    clamp(Mapped, Min, Max).

clamp(V, Min, _Max) when V < Min -> Min;
clamp(V, _Min, Max) when V > Max -> Max;
clamp(V, _, _) -> V.
