# Errm... HTTP!

A small library in erlang that handles HTTP/1.1 requests with handlers, middlewares, and more.

## Dependencies

- Erlang/OTP 28 or higher.
- libmagic, usually provided by file. (for mime guessing)

## How to use

Check [example/errm_http_demo.erl](example/errm_http_demo.erl) for a simple example.

## Run the demo

- Run `rebar3 as examples escriptize` to generate an escript of the demo.
- Run `./_build/examples/bin/errm_http_demo` to run the demo. (8080 is the port default, but you can pass any).

## TODOs

- [x] - Compression.
- [x] - Cookies.
- [ ] - Documentation.
- [ ] - Declutter.

## License

This project is licensed under the BSD 3-Clause license - see the [LICENSE](LICENSE) file for details.
