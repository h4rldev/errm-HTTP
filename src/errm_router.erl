-module(errm_router).
-export([compile/1, dispatch/2]).
-include("include/errm.hrl").

-spec compile([route()]) -> route_trie_node().
compile(Routes) ->
    compile(Routes, #{}).

-spec compile([route()], route_trie_node()) -> route_trie_node().
compile([], Trie) ->
    Trie;

compile([{Method, Path, Handler} | Rest], Trie) ->
    Normalized = [to_binary(S) || S <- Path, not is_root(to_binary(S))],
    compile(Rest, insert_route(Trie, Method, Normalized, Handler)).

to_binary(S) when is_list(S) -> list_to_binary(S);
to_binary(S) -> S.

is_root(<<>>)   -> true;
is_root(~"/") -> true;       %% ← was ~"/" (string) — should be binary
is_root(_)      -> false.

-spec insert_route(route_trie_node(), method(), path(), route_handler()) ->
    route_trie_node().

insert_route(Node, Method, [], Handler) ->
  Handlers = maps:get(handlers, Node, #{}),
  Node#{handlers => Handlers#{Method => Handler}};

insert_route(Node, Method, [<<":", Rest/binary>>], Handler) ->
  case is_wildcard(Rest) of
    true ->
      ParamName = strip_wildcard(Rest),
      Wildcards = maps:get(wildcard, Node, #{}),
      Node#{wildcard => Wildcards#{Method => {ParamName, Handler}}};
    false ->
      %% Single dynamic param :foo
      Dynamics = maps:get(dynamic, Node, []),
      case lists:keyfind(Rest, 1, Dynamics) of
        {Rest, SubNode} ->
          Updated = insert_route(SubNode, Method, [], Handler),
          Node#{dynamic => lists:keyreplace(Rest, 1, Dynamics, {Rest, Updated})};
        false ->
          SubNode = insert_route(#{}, Method, [], Handler),
          Node#{dynamic => [{Rest, SubNode} | Dynamics]}
      end
  end;

insert_route(Node, Method, [<<":", Param/binary>> | Rest], Handler) ->
  Dynamics = maps:get(dynamic, Node, []),
  case lists:keyfind(Param, 1, Dynamics) of
    {Param, SubNode} ->
      Updated = insert_route(SubNode, Method, Rest, Handler),
      Dynamic2 = lists:keyreplace(Param, 1, Dynamics, {Param, Updated});
    false ->
      SubNode = insert_route(#{}, Method, Rest, Handler),
      Dynamic2 = [{Param, SubNode} | Dynamics]
  end,
  Node#{dynamic => Dynamic2};

insert_route(Node, Method, [Segment | Rest], Handler) when is_binary(Segment) ->
  Statics = maps:get(static, Node, #{}),
  SubNode = insert_route(maps:get(Segment, Statics, #{}), Method, Rest, Handler),
  Node#{static => Statics#{Segment => SubNode}}.

-spec dispatch(route_trie_node(), request()) -> route_result().
dispatch(Node, Request = #{method := Method, path := Path}) ->
  case lookup(Node, Method, Path, #{}) of
    {ok, Params, Handler} ->
      Request2 = Request#{params := Params},
      try Handler(Request2) of
        Result -> Result
      catch
        Class:Reason:Stacktrace ->
          io:format("[errm] Error handling request: ~p:~p~n~p~n", [Class, Reason, Stacktrace]),
          {error, internal_error}
      end;
    {method_mismatch, _Params} ->
      {error, method_not_allowed};
    not_found ->
      {error, not_found}
  end.

lookup(Node, Method, [], Params) ->
  case maps:is_key(handlers, Node) of
    true ->
      Handlers = maps:get(handlers, Node),
      case maps:is_key(Method, Handlers) of
        true  -> {ok, Params, maps:get(Method, Handlers)};
        false -> {method_mismatch, Params}
      end;
    false ->
      try_wildcard_on_empty(Node, Method, Params)
  end;

lookup(Node, Method, [Segment | Rest], Params) ->
  Statics = maps:get(static, Node, #{}),
  case maps:is_key(Segment, Statics) of
    true ->
      Child = maps:get(Segment, Statics),
      case lookup(Child, Method, Rest, Params) of
        not_found -> try_other_matches(Node, Method, [Segment | Rest], Params);
        Other     -> Other
      end;
    false ->
      try_other_matches(Node, Method, [Segment | Rest], Params)
  end.

try_other_matches(Node, Method, [Segment | Rest], Params) ->
  Dynamics = maps:get(dynamic, Node, []),
  try_dynamic(Dynamics, Method, Rest, Segment, Params, Node).

try_dynamic([{ParamName, Child} | RestDyn], Method, Segments, Segment, Params, Node) ->
  Key = case ParamName of
    B when is_binary(B) -> binary_to_list(B);
    S -> S
  end,
  case lookup(Child, Method, Segments, Params#{Key => Segment}) of
    not_found -> try_dynamic(RestDyn, Method, Segments, Segment, Params, Node);
    {method_mismatch, _} = MM -> MM;
    {ok, _, _} = OK -> OK
  end;

try_dynamic([], _Method, Remaining, Segment, Params, Node) ->
  try_wildcard(Node, _Method, Segment, Remaining, Params).

try_wildcard(Node, Method, Segment, RemainingSegments, Params) ->
  case maps:find(Method, maps:get(wildcard, Node, #{})) of
    {ok, {ParamName, Handler}} ->
      AllSegments = [Segment | RemainingSegments],
      Joined = iolist_to_binary(string:join([binary_to_list(S) || S <- AllSegments], "/")),
      Key = case ParamName of
        B when is_binary(B) -> binary_to_list(B);
        S -> S
      end,
      {ok, Params#{Key => Joined}, Handler};
    error ->
      not_found
  end.

try_wildcard_on_empty(Node, Method, Params) ->
 case maps:find(Method, maps:get(wildcard, Node, #{})) of
    {ok, {ParamName, Handler}} ->
      Key = case ParamName of
        B when is_binary(B) -> binary_to_list(B);
        S -> S
      end,
      {ok, Params#{Key => <<>>}, Handler};   %% empty path → empty string
    error ->
      not_found
  end.


is_wildcard(Bin) ->
  binary:last(Bin) =:= $*.

strip_wildcard(Bin) ->
  binary:part(Bin, 0, byte_size(Bin) - 1).
