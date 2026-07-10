-module(errm_http_cors).
-export([make/1]).
-include("include/errm_http.hrl").

-type cors_origin() :: unicode:chardata() | [unicode:chardata()] | fun((unicode:chardata()) -> boolean()).
-type cors_opts() :: #{
  origins := cors_origin(),
  methods := [method()],
  headers := [unicode:chardata()],
  exposed_headers := [unicode:chardata()],
  credentials := boolean(),
  max_age := non_neg_integer()
}.

-define(ERRM_CORS_DEFAULT_METHODS, [get, post, put, delete, patch, options]).
-define(ERRM_CORS_DEFAULT_HEADERS, ["Content-Type", "Authorization", "Accept", "Origin", "X-Requested-With"]).

-spec make(cors_opts()) -> middleware().
make(Opts) ->
  Origins0 = maps:get(origins, Opts, "*"),
  Origins  = normalize_origin(Origins0),
  Methods = maps:get(methods, Opts, ?ERRM_CORS_DEFAULT_METHODS),
  RequestHeaders = maps:get(headers, Opts, ?ERRM_CORS_DEFAULT_HEADERS),
  ResponseHeaders = maps:get(exposed_headers, Opts, []),
  Credentials = maps:get(credentials, Opts, true),
  MaxAge = maps:get(max_age, Opts, 86400),

  fun(Req, Next) ->
    Origin = origin_from_request(Req),
    case origin_allowed(Origins, Origin) of
      false ->
        Next();
      true ->
        ResponseOrigin = resolved_origin(Origins, Origin),
        cors_handle(ResponseOrigin, Req, Next, Methods, RequestHeaders, ResponseHeaders, Credentials, MaxAge)
    end
end.

resolved_origin(Origins, _Origin) when is_binary(Origins), Origins =:= ~"*" -> ~"*";
resolved_origin(Origins, _Origin) when is_list(Origins), Origins =:= "*" -> ~"*";
resolved_origin(_, Origin) -> to_binary(Origin).

normalize_origin(B) when is_list(B) ->
    [to_binary(O) || O <- B];
normalize_origin(B) when is_binary(B) ->
    to_binary(B);
normalize_origin(Fun) when is_function(Fun, 1) ->
    Fun.

to_binary(S) when is_list(S) -> list_to_binary(S);
to_binary(S) -> S.

cors_handle(Origin, #{method := options} = Req, _Next, Methods, RequestHeaders, ResponseHeaders, Credentials, MaxAge) ->
  ReqHeaders = maps:get(~"access-control-request-headers", maps:get(headers, Req, #{}), ~""),
  AllowedReq = intersect_headers(ReqHeaders, RequestHeaders),
  Hdrs = cors_response_headers(Origin, Methods, AllowedReq, ResponseHeaders, Credentials, MaxAge),
  {ok, {204, Hdrs, <<>>}};
cors_handle(Origin, _Req, Next, Methods, RequestHeaders, ResponseHeaders, Credentials, MaxAge) ->
  case Next() of
    {ok, {Status, Headers, Body}} ->
      CORS = cors_response_headers(Origin, Methods, RequestHeaders, ResponseHeaders, Credentials, MaxAge),
      {ok, {Status, maps:merge(Headers, CORS), Body}};
    {error, _} = Err ->
      Err
  end.


cors_response_headers(Origin, Methods, RequestHeaders, ResponseHeaders, Credentials, MaxAge) ->
  H0 = #{
    ~"access-control-allow-origin" => Origin,
    ~"vary" => ~"Origin"
  },
  H1 = case Credentials of
    true -> H0#{~"access-control-allow-credentials" => ~"true"};
    false -> H0
  end,
  H2 = H1#{~"access-control-allow-methods" => binary_join(methods_to_binary(Methods), ~", ")},
  H3 = case RequestHeaders of
   [] -> H2;
   _  -> H2#{~"access-control-allow-headers" => binary_join(RequestHeaders, ~", ")}
  end,
  H4 = case ResponseHeaders of
    [] -> H3;
    _ -> H3#{~"access-control-expose-headers" => binary_join(ResponseHeaders, ~", ")}
  end,
  case MaxAge of
    0 -> H4;
    _ -> H4#{~"access-control-max-age" => integer_to_binary(MaxAge)}
  end.

-spec methods_to_binary([method()]) -> [unicode:chardata()].
methods_to_binary(Methods) ->
    [string:uppercase(atom_to_binary(M, utf8)) || M <- Methods].

origin_allowed(~"*", _) -> true;
origin_allowed("*", _) -> true;
origin_allowed(Origin, Origin) -> true;
origin_allowed(List, Origin) when is_list(List) ->
    lists:member(Origin, List);
origin_allowed(Fun, Origin) when is_function(Fun, 1) ->
    Fun(Origin);
origin_allowed(_, _) -> false.

origin_from_request(#{headers := Hdrs}) ->
    maps:get(~"origin", Hdrs, ~"null");
origin_from_request(_) ->
    ~"null".

-spec intersect_headers(binary(), [binary()]) -> [binary()].
intersect_headers(<<>>, _Allowed) -> [];
intersect_headers(Raw, Allowed) ->
  Requested = [string:trim(S) || S <- binary:split(Raw, ~",", [global])],
  [H || H <- Allowed, lists:member(string:lowercase(H), [string:lowercase(R) || R <- Requested])].
binary_join([], _Sep) -> <<>>;
binary_join([H | T], Sep) -> iolist_to_binary([H, [[Sep, X] || X <- T]]).
