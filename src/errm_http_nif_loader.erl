-module(errm_http_nif_loader).
-export([path/2]).

-define(CACHE_KEY, {?MODULE, extracted_root}).

path(Module, BaseName) ->
  case code:priv_dir(Module) of
    {error, bad_name} ->
      Root = ensure_extracted(),
      filename:join([Root, "lib", atom_to_list(Module), "priv", BaseName]);
    PrivDir ->
      filename:join([PrivDir, BaseName])
  end.

ensure_extracted() ->
  case persistent_term:get(?CACHE_KEY, undefined) of
    undefined ->
      Script = escript:script_name(),
      if Script == undefined ->
        erlang:error(no_escript_to_extract);
        true ->
          {ok, Sections} = escript:extract(Script, [{section, [body]}]),
          ZipBinary = case proplists:get_value(zip, Sections) of
            Zip when is_binary(Zip) -> Zip
          end,
          TempDir = create_temp_dir(),
          ok = zip:unzip(ZipBinary, [{cwd, TempDir}]),
          persistent_term:put(?CACHE_KEY, TempDir),
          TempDir
      end;
    Root -> Root
  end.


create_temp_dir() ->
  Base = case os:getenv("TMPDIR") of
    false -> case os:getenv("TEMP") of
      false -> "/tmp";
      T -> T
    end;
    T -> T
  end,
  Ts = calendar:system_time_to_rfc3339(erlang:system_time(second), [{offset, "Z"}]),
  Ts1 = re:replace(Ts, "\\s+", "_", [global, {return, list}]),
  Suffix = integer_to_list(erlang:unique_integer([positive])),
  Dir = filename:join([Base, "escript_extract_" ++ Ts1 ++ "_" ++ Suffix]),
  case file:make_dir(Dir) of
    ok -> Dir;
    {error, eexist} -> create_temp_dir();
    {error, Reason} -> erlang:error({temp_dir_failed, Reason})
  end.
