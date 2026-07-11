-module(errm_http_cookie).
-export([with_cookies/0]).
-export([set_cookie/2, set_cookie/3]).
-export([add_cookies/2]).
-include("include/errm_http.hrl").


-spec with_cookies() -> CookieMiddleware :: middleware().
with_cookies() ->
  fun(Request, Next) ->
    Cookies = parse_cookie_header(maps:get(<<"cookie">>, maps:get(headers, Request, #{}), undefined)),
    Req1 = Request#{cookies => Cookies},
    Next(Req1)
  end.


-spec set_cookie(Name :: binary(), Value :: binary()) -> binary().
set_cookie(Name, Value) -> set_cookie(Name, Value, #{}).

-spec set_cookie(Name :: binary(), Value :: binary(), CookieOpts :: cookie_opts()) -> binary().
set_cookie(Name, Value, CookieOpts) ->
  Parts = [Name, <<"=">>, Value],
  Parts1 = add_attrs(Parts, CookieOpts),
  iolist_to_binary(Parts1).


-spec add_cookies(response(), [binary() | {binary(), binary()} | {binary(), binary(), cookie_opts()}]) -> response().
add_cookies({Status, Headers0, Body}, Cookies) ->
    Headers = maps:fold(fun(K, V, Acc) -> Acc#{K => V} end, #{}, Headers0),
    NewHeaders = fold_cookies(Headers, Cookies),
    {Status, NewHeaders, Body}.


-spec fold_cookies(headers(), [binary() | {binary(), binary()} | {binary(), binary(), cookie_opts()}]) -> headers().
fold_cookies(Headers, []) ->
    Headers;
fold_cookies(Headers, [Cookie | Rest]) ->
    Header = cookie_to_header(Cookie),
    NewHeaders = merge_header(<<"set-cookie">>, Header, Headers),
    fold_cookies(NewHeaders, Rest).


-spec cookie_to_header(binary() | {binary(), binary()} | {binary(), binary(), cookie_opts()}) -> binary().
cookie_to_header({Name, Value}) when is_binary(Name), is_binary(Value) ->
    set_cookie(Name, Value);
cookie_to_header({Name, Value, Opts}) when is_binary(Name), is_binary(Value) ->
    set_cookie(Name, Value, Opts);
cookie_to_header(Bin) when is_binary(Bin) ->
    Bin.


-spec merge_header(Key :: binary(), Value :: binary(), Headers :: headers()) -> Headers :: headers().
merge_header(Key, Value, Headers) ->
  case maps:is_key(Key, Headers) of
    true ->
      case maps:get(Key, Headers) of
        Existing when is_list(Existing) -> Headers#{Key => Existing ++ [Value]};
        Existing -> Headers#{Key => [Existing, Value]}
      end;
    false ->
      Headers#{Key => Value}
  end.

add_attrs(Parts, Opts) ->
  P1 = case maps:get(path, Opts, undefined) of
    undefined -> Parts;
    P -> Parts ++ [<<"; Path=">>, P]
  end,
  P2 = case maps:get(domain, Opts, undefined) of
    undefined -> P1;
    D -> P1 ++ [<<"; Domain=">>, D]
  end,
  P3 = case maps:get(max_age, Opts, undefined) of
    undefined -> P2;
    MA -> P2 ++ [<<"; Max-Age=">>, integer_to_binary(MA)]
  end,
  P4 = case maps:get(expires, Opts, undefined) of
    undefined -> P3;
    DT -> P3 ++ [<<"; Expires=">>, format_http_date(DT)]
  end,
  P5 = case maps:get(secure, Opts, false) of
    true -> P4 ++ [<<"; Secure">>];
    false -> P4
  end,
  P6 = case maps:get(http_only, Opts, false) of
    true -> P5 ++ [<<"; HttpOnly">>];
    false -> P5
  end,

  case maps:get(same_site, Opts, undefined) of
    undefined -> P6;
    lax -> P6 ++ [<<"; SameSite=Lax">>];
    strict -> P6 ++ [<<"; SameSite=Strict">>];
    none -> P6 ++ [<<"; SameSite=None">>]
  end.

format_http_date({{Y, M, D}, {H, Min, S}}) ->
  DayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
  MonthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
  DayIdx = ((D + ((13 * (M + 1)) div 5) + Y + (Y div 4) - (Y div 100) + (Y div 400)) rem 7) + 1,
  iolist_to_binary(io_lib:format("~s, ~2.2.0B ~s ~4.4.0B ~2.2.0B:~2.2.0B:~2.2.0B GMT",
    [lists:nth(DayIdx, DayNames), D, lists:nth(M, MonthNames), Y, H, Min, S])).




parse_cookie_header(undefined) -> #{};
parse_cookie_header(CookieHeader) when is_binary(CookieHeader) ->
  parse_pairs(binary:split(CookieHeader, <<"; ">>, [global]), #{}).


parse_pairs([], Acc) -> Acc;
parse_pairs([CookiePair | Rest], Acc) ->
  case binary:split(CookiePair, <<"=">>) of
    [Name, Value] -> parse_pairs(Rest, Acc#{trim(Name) => trim(Value)});
    [Name] -> parse_pairs(Rest, Acc#{trim(Name) => <<>>})
  end.


trim(Binary) -> string:trim(Binary).
