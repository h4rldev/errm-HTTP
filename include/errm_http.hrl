-ifndef(ERRM_HTTP_HRL).
-define(ERRM_HTTP_HRL, true).
-define(MODULE_SECRETS, errm_http_secrets).

-type method() :: get | post | put | delete | patch | options | head.
-type path() :: [unicode:chardata()].

-type headers() :: #{unicode:chardata() => unicode:chardata() | [unicode:chardata()]}.
-type request() :: #{
  method := method(),
  path := path(),
  raw_path := binary(),
  headers := headers(),
  body := binary(),
  params := #{binary() => binary()},
  peer := {inet:ip_address(), inet:port_number()},
  cookies := #{binary() => binary()}
}.

-type response() :: {pos_integer(), headers(), iodata()}.
-type route_result() ::
  {ok, response()} |
  {error, atom()}.

-type next_fun() :: fun((request()) -> route_result()).
-type middleware() :: fun((request(), next_fun()) -> route_result()).
-type route_handler() :: fun((request()) -> route_result()).
-type route() :: {method(), path(), route_handler()}.
-type route_trie_node() :: #{
  handlers => #{method() => route_handler()},
  static => #{binary() => route_trie_node()},
  dynamic => [{binary(), route_trie_node()}],
  wildcard => #{method() => {binary(), route_handler()}}
}.

-type cookie_opts() :: #{
  path => binary(),
  domain => binary(),
  max_age => non_neg_integer(),
  expires => calendar:datetime(),
  secure => boolean(),
  http_only => boolean(),
  same_site => lax | strict | none,
  signed => boolean()
}.

-type cookie() :: #{
  value := binary(),
  opts := cookie_opts(),
  signed := boolean(),
  created_at => non_neg_integer()
}.

-type cookie_jar() :: #{binary() => cookie()}.

-type encoding() :: gzip | deflate | zstd | brotli.
-type compress_opts() :: #{
  preferred => [encoding()],
  compression_level => 0..9,
  min_length => non_neg_integer()
}.

-type decompress_opts() :: #{
  allowed => [encoding()]
}.

-type options() :: #{
    server_name => unicode:chardata(),
    port => non_neg_integer(),
    routes => [route()],
    middleware => [middleware()],
    acceptor_count => pos_integer()
}.
-endif.
