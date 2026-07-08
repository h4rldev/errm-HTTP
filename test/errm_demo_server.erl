-module(errm_demo_server).
-export([start/0, start/1, stop/0]).

-spec start() -> {ok, pid()}.
start() ->
  start(8080).

-spec start(pos_integer()) -> {ok, pid()}.
start(Port) ->
  Routes = [
    {get, [":path*"], errm_file:serve_dir("site-root")},
    {get, ["hello"], fun hello_handler/1},
    {get, ["users", ":id"], fun user_handler/1}
  ],

  CORS = errm_cors:make(#{
    origins => "*",
    methods => [get, post, put, delete, patch, options],
    headers => ["Content-Type", "Authorization", "Accept", "Origin"],
    exposed_headers => [],
    credentials => false,
    max_age => 86400
  }),

  {ok, Pid} = errm:start(#{
      server_name => "errm... HTTP!",
      port => Port,
      routes => Routes,
      middleware => [CORS]
  }),

  io:format("Server started at http://localhost:~B/~n", [Port]),
  io:format("\t GET /          -> index~n"),
  io:format("\t GET /hello     -> hello~n"),
  io:format("\t GET /users/:id -> Get a user~n"),

  {ok, Pid}.

stop() ->
  errm:stop(),
  io:format("Server stopped~n").

%% index_handler(_Req) -> {ok, {200, #{"content-type" => "text/html"}, "<h1>Hello World, This server is running on errm... HTTP!</h1>"}}.
hello_handler(_Req) -> {ok, {200, #{"content-type" => "text/plain"}, "Hello, World!"}}.
user_handler(#{params := #{"id" := Id}}) ->
  Id1 = binary_to_integer(Id),
  {ok, {200, #{"content-type" => "text/plain"}, io_lib:format("You're currently viewing User: ~w", [Id1])}}.

