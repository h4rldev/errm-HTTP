set quiet
set shell := ["bash", "-c"]

c_flags_mac := "-I/opt/local/include"
ld_flags_mac := "-L/opt/local/lib"

prod_c_flags := "-O2 -flto"
prod_link := "-Wl,-O2 -flto"

debug_c_flags := "-ggdb -g -Og"
debug_link := debug_c_flags + " -Wl,--no-as-needed -Wl,--gc-sections -Wl,-z,relro -Wl,-z,now"

green := "\\x1b[32m"
red := "\\x1b[31m"
clear := "\\x1b[0m"

zstd_available := shell("if pkg-config --exists libzstd 2>/dev/null; then echo yes; else echo no; fi")
brotli_available := shell("if pkg-config --exists libbrotlienc 2>/dev/null && pkg-config --exists libbrotlidec 2>/dev/null; then echo yes; else echo no; fi")

__print_yes:
    echo -ne "{{ green }}yes{{ clear }}"

__print_no:
    echo -ne "{{ red }}no{{ clear }}"

__print_missing:
    echo -e "[{{ red }}lib missing{{ clear }}]"

clean_nifs:
    rm priv/*

[parallel]
[unix]
build_nifs profile="debug": (build_magic profile) (build_zstd_if_available profile) (build_brotli_if_available profile)
    echo -e "\nUsed profile: {{ green }}{{ profile }} {{ clear }}"
    echo -ne "priv/errm_http_magic_nif.so  -> exists: "
    if [ -f "priv/errm_http_magic_nif.so" ]; then just __print_yes; echo ''; else just __print_no; echo "build_failed" > "check.txt"; fi;
    echo -ne "priv/errm_http_zstd_nif.so   -> exists: "
    if [ -f "priv/errm_http_zstd_nif.so" ]; then just __print_yes; else just __print_no; {{ if zstd_available == "yes" { "echo ''; echo 'build_failed' > 'check.txt';" } else { "echo -n ' '; just __print_missing;" } }} fi;
    echo -ne "priv/errm_http_brotli_nif.so -> exists: "
    if [ -f "priv/errm_http_brotli_nif.so" ]; then just __print_yes; else just __print_no; {{ if brotli_available == "yes" { "echo ''; echo 'build_failed' > 'check.txt';" } else { "echo -n ' '; just __print_missing;" } }} fi;
    if [ -f "check.txt" ]; then rm "check.txt"; echo -e "build_nifs: Some builds {{ red }}failed{{ clear }}"; fi

[unix]
build_magic profile="debug":
    if gcc -o priv/errm_http_magic_nif.so -shared -fPIC \
    {{ if profile == "prod" { prod_c_flags } else { debug_c_flags } }} \
    -I${ERL_ROOT}/usr/include -L${ERL_ROOT}/usr/lib \
    {{ if profile == "prod" { prod_link } else { debug_link } }} \
    -lmagic c_src/errm_http_magic_nif.c; then \
    echo -e "c_src/errm_http_magic_nif.c  -> priv/errm_http_magic_nif.so  [{{ green }}done{{ clear }}]"; \
    {{ if profile == "prod" { "strip --strip-unneeded priv/errm_http_magic_nif.so;" } else { "echo -e 'Skipping strip...';" } }} \
    else \
    echo -e "c_src/errm_http_magic_nif.c  -> priv/errm_http_magic_nif.so  [{{ red }}failed{{ clear }}]"; \
    fi

[unix]
build_zstd_if_available profile="debug":
    {{ if zstd_available == "yes" { "just build_zstd profile" } else { "echo -e 'zstd not found; skipping zstd NIF'; exit 0;" } }}
[unix]
build_brotli_if_available profile="debug":
    {{ if brotli_available == "yes" { "just build_brotli profile" } else { "echo -e 'brotli not found; skipping brotli NIF'; exit 0;" } }}

[unix]
build_zstd profile="debug":
    if gcc -o priv/errm_http_zstd_nif.so -shared -fPIC \
      {{ if profile == "prod" { prod_c_flags } else { debug_c_flags } }} \
      -I${ERL_ROOT}/usr/include -L${ERL_ROOT}/usr/lib \
      {{ if profile == "prod" { prod_link } else { debug_link } }} \
      -lzstd c_src/errm_http_zstd_nif.c; then \
    echo -e "c_src/errm_http_zstd_nif.c   -> priv/errm_http_zstd_nif.so   [{{ green }}done{{ clear }}]"; \
    {{ if profile == "prod" { "strip --strip-unneeded priv/errm_http_zstd_nif.so;" } else { "echo -e 'Skipping strip...';" } }} \
    else \
    echo -e "c_src/errm_http_zstd_nif.c   -> priv/errm_http_zstd_nif.so   [{{ red }}failed{{ clear }}]"; \
    fi

[unix]
build_brotli profile="debug":
    if gcc -o priv/errm_http_brotli_nif.so -shared -fPIC \
    {{ if profile == "prod" { prod_c_flags } else { debug_c_flags } }} \
    -I${ERL_ROOT}/usr/include -L${ERL_ROOT}/usr/lib \
    {{ if profile == "prod" { prod_link } else { debug_link } }} \
    -lbrotlicommon -lbrotlienc -lbrotlidec c_src/errm_http_brotli_nif.c; then \
    echo -e "c_src/errm_http_brotli_nif.c -> priv/errm_http_brotli_nif.so [{{ green }}done{{ clear }}]"; \
    {{ if profile == "prod" { "strip --strip-unneeded priv/errm_http_brotli_nif.so;" } else { "echo -e 'Skipping strip...';" } }} \
    else \
    echo -e "c_src/errm_http_brotli_nif.c -> priv/errm_http_brotli_nif.so [{{ red }}failed{{ clear }}]"; \
    fi

[macos]
[parallel]
build_nifs profile="debug": (build_magic profile) (build_zstd profile) (build_brotli profile)

[macos]
build_magic profile="debug":
    gcc -o priv/errm_http_magic_nif.so -shared -fPIC \
    {{ if profile == "prod" { c_flags_mac + " " + prod_c_flags } else { c_flags_mac + " " + debug_c_flags } }} \
    -I${ERL_ROOT}/usr/include -L${ERL_ROOT}/usr/lib \
    {{ if profile == "prod" { ld_flags_mac + " " + prod_link } else { ld_flags_mac + " " + debug_link } }} \
    -lmagic c_src/errm_http_magic_nif.c

[macos]
build_zstd profile="debug":
    gcc -o priv/errm_http_zstd_nif.so -shared -fPIC \
    {{ if profile == "prod" { c_flags_mac + " " + prod_c_flags } else { c_flags_mac + " " + debug_c_flags } }} \
    -I${ERL_ROOT}/usr/include -L${ERL_ROOT}/usr/lib \
    {{ if profile == "prod" { ld_flags_mac + " " + prod_link } else { ld_flags_mac + " " + debug_link } }} \
    -lzstd c_src/errm_http_zstd_nif.c

[macos]
build_brotli profile="debug":
    gcc -o priv/errm_http_brotli_nif.so -shared -fPIC \
    {{ if profile == "prod" { c_flags_mac + " " + prod_c_flags } else { c_flags_mac + " " + debug_c_flags } }} \
    -I${ERL_ROOT}/usr/include -L${ERL_ROOT}/usr/lib \
    {{ if profile == "prod" { ld_flags_mac + " " + prod_link } else { ld_flags_mac + " " + debug_link } }} \
    -lbrotlicommon -lbrotlienc -lbrotlidec c_src/errm_http_brotli_nif.c

bear:
    bear -- just build_nifs
