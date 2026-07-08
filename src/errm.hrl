-ifndef(ERRM_HRL).
-define(ERRM_HRL, true).

-type method() :: get | post | put | delete | patch | options | head.
-type path() :: [unicode:chardata()].

-type headers() :: #{unicode:chardata() => unicode:chardata()}.
-type request() :: #{
  method := method(),
  path := path(),
  raw_path := binary(),
  headers := headers(),
  body := binary(),
  params := #{binary() => binary()},
  peer := {inet:ip_address(), inet:port_number()}
}.

-type response() :: {pos_integer(), headers(), iodata()}.
-type route_result() ::
  {ok, response()} |
  {error, atom()}.

-type next_fun() :: fun(() -> route_result()).
-type middleware() :: fun((request(), next_fun()) -> route_result()).
-type route_handler() :: fun((request()) -> route_result()).
-type route() :: {method(), path(), route_handler()}.
-type route_trie_node() :: #{
  handlers => #{method() => route_handler()},
  static => #{binary() => route_trie_node()},
  dynamic => [{binary(), route_trie_node()}]
}.


-type options() :: #{
    port => non_neg_integer(),
    routes => [route()],
    middleware => [middleware()],
    acceptor_count => pos_integer()
}.
-endif.
