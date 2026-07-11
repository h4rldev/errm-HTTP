-module(errm_http_cookie_jar).
-export([new/0]).
-export([put/3, put/4]).
-export([get/2]).
-export([to_headers/1, to_headers/2]).
-export([from_request/2]).
-export([verify/2]).
-export([sign/2, unsign/2]).
-include("include/errm_http.hrl").

-export_type([cookie/0, cookie_jar/0]).

-define (DEFAULT_COOKIE_OPTS, #{signed => false}).

-spec new() -> CookieJar :: cookie_jar().
new() -> #{}.

-spec put(CookieJar :: cookie_jar(), Name :: binary(), Value :: binary(), CookieOpts :: cookie_opts()) -> CookieJar :: cookie_jar().
put(CookieJar, Name, Value, CookieOpts) ->
  Signed = maps:get(signed, CookieOpts, false),
  Created = erlang:system_time(second),
  CookieJar#{Name => #{value => Value, opts => CookieOpts, signed => Signed, created_at => Created}}.

-spec put(CookieJar :: cookie_jar(), Name :: binary(), Value :: binary()) -> CookieJar :: cookie_jar().
  put(CookieJar, Name, Value) ->
    put(CookieJar, Name, Value, ?DEFAULT_COOKIE_OPTS).


-spec get(CookieJar :: cookie_jar(), Name :: binary()) -> binary() | undefined.
get(CookieJar, Name) ->
  case maps:is_key(Name, CookieJar) of
    true ->
      Cookie = maps:get(Name, CookieJar),
      case is_expired(Cookie) of
        false -> maps:get(value, Cookie);
        true -> undefined
      end;
    false -> undefined
  end.


-spec to_headers(CookieJar :: cookie_jar()) -> Headers :: [binary()].
  to_headers(CookieJar) ->
    to_headers(CookieJar, undefined).


-spec to_headers(CookieJar :: cookie_jar(), Secret :: binary() | undefined) -> Headers :: [binary()].
to_headers(CookieJar, Secret) ->
  maps:fold(fun(Name, Cookie, Acc) ->
    Value = maps:get(value, Cookie),
    Opts = maps:get(opts, Cookie),
    Signed = maps:get(signed, Cookie, false),  %% read from the cookie record
    FinalValue = case Signed andalso Secret =/= undefined of
      true -> sign(Value, Secret);
      false -> Value
    end,
    Header = errm_http_cookie:set_cookie(Name, FinalValue, Opts),
    [Header | Acc]
  end, [], CookieJar).


-spec from_request(Request :: request(), Secret :: binary() | undefined) -> CookieJar :: cookie_jar().
from_request(Request, Secret) ->
  RawCookies = maps:get(cookies, Request, #{}),
  maps:fold(fun(Name, Value, CookieJar) ->
    case Secret of
      undefined -> put(CookieJar, Name, Value);
      _ when is_binary(Secret) ->
        case is_signed(Name) of
          true ->
            case unsign(Value, Secret) of
              {ok, Unsigned} ->
                put(CookieJar, Name, Unsigned, #{signed => true});
              {error, _} ->
                CookieJar
            end;
          false ->
            put(CookieJar, Name, Value)
        end
    end
  end, #{}, RawCookies).


-spec sign(Value :: binary(), Secret :: binary()) -> binary().
sign(Value, Secret) ->
  Mac = crypto:mac(hmac, sha256, Secret, Value),
  <<Value/binary, ".", (base64:encode(Mac, #{mode => 'urlsafe', padding => false}))/binary>>.


-spec unsign(Value :: binary(), Secret :: binary()) -> {ok, binary()} | {error, term()}.
unsign(Value, Secret) ->
  case binary:split(Value, <<".">>) of
    [Raw, Signature] ->
      Expected = crypto:mac(hmac, sha256, Secret, Raw),
      case constant_time_equal(Expected, base64:decode(Signature, #{mode => 'urlsafe', padding => false})) of
        true -> {ok, Raw};
        false -> {error, invalid_signature}
      end;
    _ -> {error, not_signed}
  end.


-spec verify(CookieVal :: binary(), Secret :: binary()) -> boolean().
verify(CookieVal, Secret) ->
  case unsign(CookieVal, Secret) of
    {ok, _} -> true;
    _ -> false
  end.


constant_time_equal(A, B) when byte_size(A) =:= byte_size(B) ->
  constant_time_equal(A, B, 0);
constant_time_equal(_,_) -> false.

constant_time_equal(<<>>, <<>>, Acc) -> Acc =:= 0;
constant_time_equal(<<X:8, RestA/binary>>, <<Y:8, RestB/binary>>, Acc) ->
  constant_time_equal(RestA, RestB, Acc bor (X bxor Y)).

is_signed(Name) -> binary:last(Name) =:= $*.

is_expired(#{created_at := Created, opts := CookieOpts}) ->
  Now = erlang:system_time(second),
  case maps:get(max_age, CookieOpts, undefined) of
    MaxAge when is_integer(MaxAge) ->
      (Now - Created) > MaxAge;
    _ ->
      case maps:get(expires, CookieOpts, undefined) of
        Expires when is_tuple(Expires) ->
          ExpSecs = calendar:datetime_to_gregorian_seconds(Expires) -
            calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0,0,0}}),
          Now > ExpSecs;
        _ ->
          false
      end
  end.



