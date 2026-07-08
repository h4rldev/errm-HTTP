-module(errm_listener).
-behaviour(gen_server).
-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-include("errm.hrl").

-record(state, {
  listen_sock :: gen_tcp:socket() | undefined,
  port        :: non_neg_integer(),
  acceptors   :: [pid()],
  routes      :: route_trie_node(),
  middleware  :: [middleware()]
}).

-spec start_link(options()) -> {ok, pid()} | ignore | {error, term()}.
start_link(Options) ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, Options, []).


-spec init(options()) -> {ok, #state{}} | {stop, term()}.
init(Options) ->
  process_flag(trap_exit, true),
  Port = maps:get(port, Options, 8080),
  Routes = maps:get(routes, Options, []),
  Middleware = maps:get(middleware, Options, []),
  Schedulers = erlang:system_info(schedulers_online),
  AcqCount = maps:get(acceptor_count, Options, Schedulers * 2),
  RouteTree = errm_router:compile(Routes),

  case gen_tcp:listen(Port, [binary, {packet, raw}, {active, false}, {reuseaddr, true}, {nodelay, true}, {send_timeout, 30000}, {keepalive, true}, {backlog, 1024}]) of
    {ok, ListenSock} ->
      {ok, ActualPort} = inet:port(ListenSock),
      io:format("[errm] Listening on port: ~p with ~p acceptors~n", [ActualPort, AcqCount]),
      Acceptors = [spawn_acceptor(ListenSock, RouteTree, Middleware) || _ <- lists:seq(1, AcqCount)],
      {ok, #state{listen_sock=ListenSock, port=ActualPort, acceptors=Acceptors, routes=RouteTree, middleware=Middleware}};
    {error, Reason} -> {stop, {cannot_listen, Reason}}
  end.

-spec handle_call(term(), {pid(), term()}, #state{}) -> {reply, {ok, non_neg_integer()}, #state{}}.
handle_call(_Req, _From, State) ->
    {reply, {ok, State#state.port}, State}.

-spec handle_cast(term(), #state{}) -> {noreply, #state{}}.
handle_cast(_Req, State) ->
    {noreply, State}.


-spec handle_info(term(), #state{}) -> {noreply, #state{}}.
handle_info({'EXIT', Pid, Reason}, State=#state{acceptors=Accs, listen_sock=LS})
    when LS =/= undefined ->
  case lists:member(Pid, Accs) of
    true ->
      io:format("[errm] Acceptor ~p restarted with reason \"~p\"~n", [Pid, Reason]),
      New = spawn_acceptor(State#state.listen_sock, State#state.routes, State#state.middleware),
      Rest = [A || A <- Accs, A =/= Pid],
      {noreply, State#state{acceptors=[New | Rest]}};
    false ->
      {noreply, State}
  end;
handle_info({'EXIT', _Pid, _Reason}, State) ->
    {noreply, State};
handle_info(_Info, State) ->
  {noreply, State}.

-spec terminate(term(), #state{}) -> ok.
terminate(_Reason, #state{listen_sock=undefined}) -> ok;
terminate(_Reason, #state{listen_sock=Sock}) -> gen_tcp:close(Sock), ok.

-spec spawn_acceptor(gen_tcp:socket(), route_trie_node(), [middleware()]) -> pid().
spawn_acceptor(ListenSock, Routes, Middleware) ->
  spawn_link(fun() -> errm_acceptor:accept_loop(ListenSock, Routes, Middleware) end).

