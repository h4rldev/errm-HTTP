-module(errm_http_file).
-export([serve_file/2, serve_dir/1, serve_dir/2]).
-include("include/errm_http.hrl").

-spec serve_file(Root :: unicode:chardata(), FilePath :: unicode:chardata()) ->
  route_handler().
serve_file(Root, FilePath) ->
  RootStr = to_string(Root),
  FileStr = to_string(FilePath),
  FullPath = filename:join([RootStr, FileStr]),
  fun (_Req) ->
      case file:read_file(FullPath) of
        {ok, Data} ->
            MimeType = detect_mime(FullPath),
            {ok, {200, #{"content-type" => MimeType}, Data}};
        {error, _} ->
          {error, not_found}
      end
  end.

-spec serve_dir(Root :: unicode:chardata()) -> route_handler().
serve_dir(Root) ->
  serve_dir(Root, ["index.html", "index.htm"]).

-spec serve_dir(Root :: unicode:chardata(), IndexFiles :: [unicode:chardata()])
  -> route_handler().
serve_dir(Root, IndexFiles) ->
  RootStr = to_string(Root),
  IndexStrs = [to_string(I) || I <- IndexFiles],
  fun (#{params := #{"path" := Path}}) ->
    case safe_join(RootStr, Path) of
      {ok, FullPath} ->
        case file:read_file(FullPath) of
          {ok, Data} ->
            MimeType = detect_mime(FullPath),
            {ok, {200, #{"content-type" => MimeType}, Data}};
          {error, eisdir} ->
            try_index(RootStr, FullPath, IndexStrs);
          {error, _} ->
            {error, not_found}
        end;
      false ->
        {error, not_found}
    end
  end.

safe_join(Root, Path) ->
  Parts = string:split(Path, "/", all),
  Segments = [to_string(S) || S <- Parts],
  FullPath = filename:join([Root | Segments]),
  case safe_path(Root, FullPath) of
    true -> {ok, FullPath};
    false -> false
  end.

try_index(_Root, _DirPath, []) ->
  {error, not_found};
try_index(Root, DirPath, [Index | Rest]) ->
  FullPath = filename:join([DirPath, Index]),
  case safe_path(Root, FullPath) andalso file:read_file(FullPath) of
    {ok, Data} ->
      MimeType = detect_mime(FullPath),
      {ok, {200, #{"content-type" => MimeType}, Data}};
    _ ->
      try_index(Root, DirPath, Rest)
  end.

safe_path(Root, Path) ->
  AbsRoot = filename:absname(Root),
  AbsPath = filename:absname(Path),
  RootParts = filename:split(AbsRoot),
  PathParts = filename:split(AbsPath),
  lists:prefix(RootParts, PathParts).

detect_mime(Path) ->
  case errm_http_magic_nif:get_mime_type(Path) of
    {ok, Mime} -> Mime;
    {error, _} -> "application/octet-stream"
  end.

to_string(S) when is_binary(S) -> binary_to_list(S);
to_string(S) -> S.
