-module(errm_http_file).
-export([serve_file/2, serve_dir/1, serve_dir/2]).
-export([init_mime_cache/0]).
-include("include/errm_http.hrl").
-include_lib("kernel/include/file.hrl").

-define(MIME_TABLE, errm_http_mime_cache).

%% ----------------------------------------------------------------------
%% MIME cache
init_mime_cache() ->
  case ets:info(?MIME_TABLE) of
    undefined ->
      ets:new(?MIME_TABLE, [named_table, public, set, {read_concurrency, true}]),
      load_common_mimes();
    _ -> ok
  end.

load_common_mimes() ->
  Common = #{
    <<"html">>  => <<"text/html">>,
    <<"htm">>   => <<"text/html">>,
    <<"css">>   => <<"text/css">>,
    <<"js">>    => <<"application/javascript">>,
    <<"json">>  => <<"application/json">>,
    <<"png">>   => <<"image/png">>,
    <<"jpg">>   => <<"image/jpeg">>,
    <<"jpeg">>  => <<"image/jpeg">>,
    <<"gif">>   => <<"image/gif">>,
    <<"svg">>   => <<"image/svg+xml">>,
    <<"ico">>   => <<"image/x-icon">>,
    <<"txt">>   => <<"text/plain">>,
    <<"xml">>   => <<"application/xml">>,
    <<"pdf">>   => <<"application/pdf">>,
    <<"zip">>   => <<"application/zip">>,
    <<"gz">>    => <<"application/gzip">>,
    <<"br">>    => <<"application/brotli">>
  },
  ets:insert(?MIME_TABLE, maps:to_list(Common)).

-spec serve_file(Root :: unicode:chardata(), FilePath :: unicode:chardata()) -> route_handler().
serve_file(Root, FilePath) ->
  RootStr = to_string(Root),
  FileStr = to_string(FilePath),
  FullPath = filename:join([RootStr, FileStr]),
  fun(_Req) ->
    case file:read_file_info(FullPath) of
      {ok, #file_info{type = regular, size = Size}} when is_integer(Size), Size >= 0 ->
        Mime = detect_mime(FullPath),
        Headers = #{
          <<"content-type">> => Mime,
          <<"content-length">> => integer_to_binary(Size)
        },
        if
          Size < ?ERRM_CHUNK_THRESHOLD ->
            case file:read_file(FullPath) of
              {ok, Data} -> {ok, {200, Headers, Data}};
              {error, _} -> {error, not_found}
            end;
          true ->
            {ok, {200, Headers, {file, FullPath}}}
        end;
      {ok, #file_info{type = directory}} ->
        {error, not_found};
      {error, _} ->
        {error, not_found}
    end
  end.

-spec serve_dir(Root :: unicode:chardata()) -> route_handler().
serve_dir(Root) ->
  serve_dir(Root, ["index.html", "index.htm"]).

-spec serve_dir(Root :: unicode:chardata(), IndexFiles :: [unicode:chardata()]) -> route_handler().
serve_dir(Root, IndexFiles) ->
  RootStr = to_string(Root),
  IndexStrs = [to_string(I) || I <- IndexFiles],
  fun(Req = #{params := #{"path" := Path}}) ->
    case safe_join(RootStr, Path) of
      {ok, FullPath} ->
        case file:read_file_info(FullPath) of
          {ok, #file_info{type = regular, size = Size}} when is_integer(Size), Size >= 0 ->
            %% Serve the file directly
            serve_existing_file(FullPath, Size);
          {ok, #file_info{type = directory}} ->
            %% Try index files inside directory
            try_index_with_fallback(RootStr, FullPath, IndexStrs, Req);
          {error, enoent} ->
            %% File not found – try compressed variants
            serve_compressed_variant(FullPath, Req, RootStr, IndexStrs);
          {error, _} ->
            {error, not_found}
        end;
      false ->
        {error, not_found}
    end
  end.

-spec serve_existing_file(file:filename_all(), non_neg_integer()) -> route_result().
serve_existing_file(Path, Size) ->
  Mime = detect_mime(Path),
  Headers = #{
    <<"content-type">> => Mime,
    <<"content-length">> => integer_to_binary(Size)
  },
  if Size < ?ERRM_CHUNK_THRESHOLD ->
    case file:read_file(Path) of
      {ok, Data} -> {ok, {200, Headers, Data}};
      {error, _} -> {error, not_found}
    end;
  true ->
    {ok, {200, Headers, {file, Path}}}
  end.

-spec serve_compressed_variant(file:filename_all(), request(), string(), [string()]) -> route_result().
serve_compressed_variant(FullPath0, Req, RootStr, IndexStrs) ->
  FullPath = to_string(FullPath0),
  Accept = maps:get(<<"accept-encoding">>, maps:get(headers, Req, #{}), <<"">>),
  ClientEncodings = parse_accept_encoding(Accept),
  Variants = [
    {<<"br">>,     ".br"},
    {<<"zstd">>,   ".zst"},
    {<<"gzip">>,   ".gz"},
    {<<"deflate">>, ".deflate"}
  ],
  case find_first_matching_variant(ClientEncodings, Variants, FullPath) of
    {ok, VariantPath, Enc} ->
      case file:read_file_info(VariantPath) of
        {ok, #file_info{type = regular, size = Size}} when is_integer(Size), Size >= 0 ->
          Mime = detect_mime(FullPath),
          Headers = #{
            <<"content-type">> => Mime,
            <<"content-length">> => integer_to_binary(Size),
            <<"content-encoding">> => Enc,
            <<"vary">> => <<"Accept-Encoding">>
          },
          if Size < ?ERRM_CHUNK_THRESHOLD ->
            case file:read_file(VariantPath) of
              {ok, Data} -> {ok, {200, Headers, Data}};
              {error, _} -> try_index_with_fallback(RootStr, FullPath, IndexStrs, Req)
            end;
          true ->
            {ok, {200, Headers, {file, VariantPath}}}
          end;
        _ ->
          try_index_with_fallback(RootStr, FullPath, IndexStrs, Req)
      end;
    false ->
      try_index_with_fallback(RootStr, FullPath, IndexStrs, Req)
  end.

-spec find_first_matching_variant([binary()], [{binary(), string()}], string()) ->
    {ok, string(), binary()} | false.
find_first_matching_variant(ClientEncodings, Variants, FullPath) ->
  case lists:search(
    fun({Enc, Ext}) ->
      lists:member(Enc, ClientEncodings)
      andalso filelib:is_regular(FullPath ++ Ext)
    end,
    Variants
  ) of
    {value, {Enc, Ext}} -> {ok, FullPath ++ Ext, Enc};
    false -> false
  end.
try_index_with_fallback(RootStr, DirPath, IndexStrs, Req) ->
  try_index_with_threshold(RootStr, DirPath, IndexStrs, Req).

try_index_with_threshold(_RootStr, _DirPath, [], _Req) ->
  {error, not_found};
try_index_with_threshold(RootStr, DirPath, [Index | Rest], Req) ->
  FullPath = filename:join([DirPath, Index]),
  case safe_path(RootStr, FullPath) andalso file:read_file_info(FullPath) of
    {ok, #file_info{type = regular, size = Size}} when is_integer(Size), Size >= 0 ->
      serve_existing_file(FullPath, Size);
    {ok, #file_info{type = directory}} ->
      try_index_with_threshold(RootStr, DirPath, Rest, Req);
    {error, enoent} ->
      %% Index file doesn't exist – try compressed variant
      case serve_compressed_variant(FullPath, Req, RootStr, []) of
        {ok, _} = Resp -> Resp;
        _ -> try_index_with_threshold(RootStr, DirPath, Rest, Req)
      end;
    _ ->
      try_index_with_threshold(RootStr, DirPath, Rest, Req)
  end.

parse_accept_encoding(<<>>) -> [];
parse_accept_encoding(Header) ->
  Tokens = binary:split(Header, <<",">>, [global]),
  [begin
     Clean = string:trim(Token),
     encoding_atom(string:lowercase(Clean))
   end || Token <- Tokens].

encoding_atom(<<"gzip">>) -> <<"gzip">>;
encoding_atom(<<"deflate">>) -> <<"deflate">>;
encoding_atom(<<"zstd">>) -> <<"zstd">>;
encoding_atom(<<"br">>) -> <<"br">>;
encoding_atom(<<"*">>) -> <<"*">>;
encoding_atom(_) -> undefined.


safe_join(Root, Path) ->
  Parts = string:split(Path, "/", all),
  Segments = [to_string(S) || S <- Parts],
  FullPath = filename:join([Root | Segments]),
  case safe_path(Root, FullPath) of
    true -> {ok, FullPath};
    false -> false
  end.

safe_path(Root, Path) ->
  AbsRoot = filename:absname(Root),
  AbsPath = filename:absname(Path),
  RootParts = filename:split(AbsRoot),
  PathParts = filename:split(AbsPath),
  lists:prefix(RootParts, PathParts).

detect_mime(Path) ->
  Ext = case filename:extension(Path) of
    [] -> <<>>;
    ExtStr when is_list(ExtStr) ->
      Bin = list_to_binary(ExtStr),
      case Bin of
        <<$. , Rest/binary>> -> string:lowercase(Rest);
        _ -> string:lowercase(Bin)
      end
  end,
  case ets:lookup(?MIME_TABLE, Ext) of
    [{_, Mime}] -> Mime;
    [] ->
      Mime = fallback_mime(Path),
      ets:insert(?MIME_TABLE, {Ext, Mime}),
      Mime
  end.

fallback_mime(Path) ->
  case errm_http_magic_nif:get_mime_type(to_string(Path)) of
    {ok, Mime} -> list_to_binary(Mime);
    {error, _} -> <<"application/octet-stream">>
  end.

to_string(S) when is_binary(S) -> binary_to_list(S);
to_string(S) -> S.
