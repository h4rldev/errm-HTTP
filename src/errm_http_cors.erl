-module(errm_http_cors).
-export([make/1]).
-include("include/errm_http.hrl").
-export_type([cors_origin/0, cors_opts/0, cors_policy_entry/0]).

-define(ERRM_CORS_DEFAULT_METHODS, [get, post, put, delete, patch, options]).
-define(ERRM_CORS_DEFAULT_HEADERS, ["Content-Type", "Authorization", "Accept", "Origin", "X-Requested-With"]).

-spec make(cors_opts()) -> middleware().
make(Opts) ->
  PolicyList = case maps:get(policies, Opts, undefined) of
    undefined -> [Opts];
    List when is_list(List) -> List
  end,

  Defaults = #{
    allowed_methods => maps:get(methods, Opts, ?ERRM_CORS_DEFAULT_METHODS),
    allowed_headers => maps:get(headers, Opts, ?ERRM_CORS_DEFAULT_HEADERS),
    exposed_headers => maps:get(exposed_headers, Opts, []),
    credentials => maps:get(credentials, Opts, false),
    max_age => maps:get(max_age, Opts, 86400),
    vary => maps:get(vary, Opts, true)
  },

  Compiled = [compile_entry(Entry, Defaults) || Entry <- PolicyList],
  fun(Req, Next) ->
      Origin = origin_from_request(Req),
      Method = maps:get(method, Req),
      logger:debug("[CORS] Request from ~p method ~p", [Origin, Method]),
      case find_matching_policy(Compiled, Origin, Method, Req) of
        {ok, Policy} ->
          cors_handle(Origin, Req, Next, Policy);
        {error, denied} ->
          Next(Req)
      end
  end.


compile_entry(Entry, Defaults) ->
  OriginSpec = maps:get(origin, Entry),
  NormalizedOrigin = normalize_origin(OriginSpec),
  Methods = maps:get(methods, Entry, undefined),
  Headers = maps:get(headers, Entry, undefined),
  CredentialsMatch = maps:get(credentials, Entry, undefined),

  AllowOrigin = case NormalizedOrigin of
    '*' -> <<"*">>;
    _   -> true
  end,

  Policy = #{
    allowed_methods => maps:get(allowed_methods, Entry, maps:get(allowed_methods, Defaults)),
    allowed_headers => maps:get(allowed_headers, Entry, maps:get(allowed_headers, Defaults)),
    exposed_headers => maps:get(exposed_headers, Entry, maps:get(exposed_headers, Defaults)),
    credentials => maps:get(credentials, Entry, maps:get(credentials, Defaults)),
    max_age => maps:get(max_age, Entry, maps:get(max_age, Defaults)),
    vary => maps:get(vary, Entry, maps:get(vary, Defaults)),
    allow_origin => AllowOrigin
  },

  AllowedHeadersBin = [to_binary(H) || H <- maps:get(allowed_headers, Policy)],
  AllowedHeadersSet = ordsets:from_list([string:lowercase(H) || H <- AllowedHeadersBin]),

  #{
    origin => NormalizedOrigin,
    methods => Methods,
    headers => Headers,
    credentials_match => CredentialsMatch,
    allowed_headers_set => AllowedHeadersSet,
    policy => Policy
   }.

find_matching_policy([], _Origin, _Method, _Req) ->
  {error, denied};
find_matching_policy([Entry | Rest], Origin, Method, Req) ->
  case origin_allowed(maps:get(origin, Entry), Origin) of
    false ->
      find_matching_policy(Rest, Origin, Method, Req);
    {true, _Creds} ->
      case Method of
        options ->
          case maps:get(headers, Entry, undefined) of
            undefined ->
              {ok, maps:get(policy, Entry)};
            [] ->
              {ok, maps:get(policy, Entry)};
            RequiredHeaders when is_list(RequiredHeaders) ->
              ReqHeaders = maps:get(
                <<"access-control-request-headers">>,
                maps:get(headers, Req, #{}),
                <<"">>
              ),
              case ReqHeaders of
                <<"">> ->
                  {ok, maps:get(policy, Entry)};
                _ ->
                  ReqSet = ordsets:from_list([
                    string:lowercase(string:trim(S)) ||
                    S <- binary:split(ReqHeaders, <<",">>, [global])
                  ]),
                  RequiredSet = ordsets:from_list([
                    string:lowercase(to_binary(H)) || H <- RequiredHeaders
                  ]),
                  case ordsets:intersection(ReqSet, RequiredSet) of
                    [] -> find_matching_policy(Rest, Origin, Method, Req);
                    _  -> {ok, maps:get(policy, Entry)}
                  end
              end
          end;
        _ ->
          {ok, maps:get(policy, Entry)}
      end
  end.



cors_handle(Origin, #{method := options} = Req, _Next, Policy) ->
  ReqHeaders = maps:get(
    <<"access-control-request-headers">>,
    maps:get(headers, Req, #{}),
    <<"">>
  ),
  AllowedSet = maps:get(allowed_headers_set, Policy, ordsets:new()),
  AllowedReq = case AllowedSet of
    [] ->
      case ReqHeaders of
        <<"">> -> [];
        _ ->
          [to_binary(string:lowercase(string:trim(S))) ||
           S <- binary:split(ReqHeaders, <<",">>, [global]),
           S =/= <<"">>]
      end;
    _ ->
      intersect_headers(ReqHeaders, AllowedSet)
  end,
  Hdrs = cors_response_headers(Origin, Policy, AllowedReq),
  {ok, {204, Hdrs, <<>>}};

cors_handle(Origin, Req, Next, Policy) ->
  case Next(Req) of
    {ok, {Status, Headers, Body}} ->
      CORS = cors_response_headers(Origin, Policy, []),
      {ok, {Status, maps:merge(Headers, CORS), Body}};
    {error, _} = Err ->
      Err
  end.


-spec cors_response_headers(binary(), cors_policy_entry(), [binary()]) -> headers().
cors_response_headers(Origin, Policy, ReqHeaders) ->
  AllowOrigin = maps:get(allow_origin, Policy, true),
  Creds = maps:get(credentials, Policy, false),
  Methods = maps:get(allowed_methods, Policy, ?ERRM_CORS_DEFAULT_METHODS),
  ExposedHeaders = maps:get(exposed_headers, Policy, []),
  MaxAge = maps:get(max_age, Policy, 86400),
  Vary = maps:get(vary, Policy, true),

  H0 = 
    case AllowOrigin of
      true -> #{<<"access-control-allow-origin">> => Origin};
      false -> #{};
      OriginBin when is_binary(OriginBin) -> #{<<"access-control-allow-origin">> => OriginBin}
    end,
  H1 = 
    case Vary andalso H0 =/= #{} of
      true -> H0#{<<"vary">> => <<"Origin">>};
      false -> H0
    end,
  H2 = 
    case Creds of
      true -> H1#{<<"access-control-allow-credentials">> => <<"true">>};
      false -> H1
    end,
  H3 = H2#{<<"access-control-allow-methods">> => binary_join(methods_to_binary(Methods), <<", ">>)},
  H4 = 
    case ReqHeaders of
      [] -> H3;
      _  -> H3#{<<"access-control-allow-headers">> => binary_join(ReqHeaders, <<", ">>)}
    end,
  H5 = 
    case ExposedHeaders of
      [] -> H4;
      _  -> H4#{<<"access-control-expose-headers">> => binary_join(ExposedHeaders, <<", ">>)}
    end,
  case MaxAge of
    0 -> H5;
    _ -> H5#{<<"access-control-max-age">> => integer_to_binary(MaxAge)}
  end.


normalize_origin('*') -> '*';
normalize_origin("*") -> '*';
normalize_origin(<<"*">>) -> '*';
normalize_origin(B) when is_list(B) ->
  [to_binary(O) || O <- B];
normalize_origin(B) when is_binary(B) ->
  to_binary(B);
normalize_origin(Fun) when is_function(Fun, 1) -> Fun.

origin_allowed('*', _) -> {true, false};
origin_allowed(Allowed, Origin) when is_binary(Allowed) ->
  {Allowed =:= Origin, false};
origin_allowed(List, Origin) when is_list(List) ->
  case lists:member(Origin, List) of
    true -> {true, false};
    false -> false
  end;
origin_allowed(Fun, Origin) when is_function(Fun, 1) ->
  case Fun(Origin) of
    {true, Creds} when is_boolean(Creds)
          -> {true, Creds};
    true  -> {true, false};
    false -> false;
    _     -> false
  end.

origin_from_request(Req) ->
  maps:get(<<"origin">>, maps:get(headers, Req, #{}), <<"null">>).

intersect_headers(<<>>, _AllowedSet) -> [];
intersect_headers(Raw, AllowedSet) ->
  Requested = [string:lowercase(string:trim(S)) || S <- binary:split(Raw, <<",">>, [global])],
  RequestedSet = ordsets:from_list(Requested),
  lists:sort(ordsets:to_list(ordsets:intersection(AllowedSet, RequestedSet))).

to_binary(S) when is_list(S) -> list_to_binary(S);
to_binary(S) -> S.

methods_to_binary(Methods) ->
  [string:uppercase(atom_to_binary(M, utf8)) || M <- Methods].

binary_join([], _Sep) -> <<>>;
binary_join([H | T], Sep) -> iolist_to_binary([H, [[Sep, X] || X <- T]]).
