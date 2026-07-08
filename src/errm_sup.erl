-module(errm_sup).
-behaviour(supervisor).
-export([start_link/1, init/1, stop/0]).
-include("errm.hrl").

-spec start_link(options()) -> {ok, pid()} | ignore | {error, term()}.
start_link(Options) ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, Options).

-spec init(options()) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init(Options) ->
  Listener = #{
    id => errm_listener,
    start => {errm_listener, start_link, [Options]},
    restart => permanent,
    shutdown => 5000,
    type => worker,
    modules => [errm_listener]
  },
  {ok, {#{strategy => one_for_one, intensity => 1, period => 5}, [Listener]}}.


-spec stop() -> ok.
stop() ->
  supervisor:terminate_child(?MODULE, errm_listener),
  ok.
