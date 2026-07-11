-module(errm_http_router).
-export([compile/1, dispatch/2]).
-include("include/errm_http.hrl").

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
is_root(<<"/">>) -> true;
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
      Dynamics = maps:get(dynamic, Node, #{}),
      SubNode = maps:get(Rest, Dynamics, #{}),
      UpdatedSub = insert_route(SubNode, Method, [], Handler),
      Node#{dynamic => Dynamics#{Rest => UpdatedSub}}
  end;

insert_route(Node, Method, [<<":", Param/binary>> | Rest], Handler) ->
  Dynamics = maps:get(dynamic, Node, #{}),
  SubNode = maps:get(Param, Dynamics, #{}),
  UpdatedSub = insert_route(SubNode, Method, Rest, Handler),
  Node#{dynamic => Dynamics#{Param => UpdatedSub}};

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
          logger:error("[errm] Error handling request:"),
          logger:error("[errm] ~p", [Class]),
          logger:error("[errm] ~p", [Reason]),
          logger:error("[errm] ~p", [Stacktrace]),
          {error, internal_error}
      end;
    {method_mismatch, _Params} -> {error, method_not_allowed};
    {internal_error, _Params} ->
      {error, internal_error};
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
    try_dynamic(Node, Method, Rest, Segment, Params).

try_dynamic(Node, Method, Segments, Segment, Params) ->
    Dynamics = maps:get(dynamic, Node, #{}),
    case maps:size(Dynamics) of
        0 ->
            try_wildcard(Node, Method, Segment, Segments, Params);
        _ ->
            case try_dynamic_list(maps:to_list(Dynamics), Method, Segments, Segment, Params) of
                not_found ->
                    try_wildcard(Node, Method, Segment, Segments, Params);
                Other ->
                    Other
            end
    end.

try_dynamic_list([], _Method, _Segments, _Segment, _Params) ->
    not_found;
try_dynamic_list([{ParamName, Child} | RestDyn], Method, Segments, Segment, Params) ->
    case lookup(Child, Method, Segments, add_param(Params, ParamName, Segment)) of
        not_found ->
            try_dynamic_list(RestDyn, Method, Segments, Segment, Params);
        {method_mismatch, _} = MM ->
            MM;
        {ok, _, _} = OK ->
            OK
    end.

try_wildcard(Node, Method, Segment, RemainingSegments, Params) ->
  case maps:find(Method, maps:get(wildcard, Node, #{})) of
    {ok, {ParamName, Handler}} ->
      AllSegments = [Segment | RemainingSegments],
      Joined = iolist_to_binary(string:join([binary_to_list(S) || S <- AllSegments], "/")),
      {ok, add_param(Params, ParamName, Joined), Handler};
    error ->
      not_found
  end.

try_wildcard_on_empty(Node, Method, Params) ->
 case maps:is_key(Method, maps:get(wildcard, Node, #{})) of
    true ->
      {ParamName, Handler} = maps:get(Method, maps:get(wildcard, Node, #{})),
      {ok, add_param(Params, ParamName, <<>>), Handler};
    false ->
      not_found
  end.

add_param(Params, Key, Value) when is_binary(Key) ->
    Params#{Key => Value, binary_to_list(Key) => Value}.
is_wildcard(Bin) ->
  binary:last(Bin) =:= $*.

strip_wildcard(Bin) ->
  binary:part(Bin, 0, byte_size(Bin) - 1).
