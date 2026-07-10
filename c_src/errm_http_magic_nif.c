#include <erl_nif.h>
#include <magic.h>
#include <stdio.h>

typedef ERL_NIF_TERM erl_nif_term_t;
typedef ErlNifEnv erl_nif_env_t;
typedef ErlNifBinary erl_nif_binary_t;
typedef ErlNifFunc erl_nif_func_t;
typedef ErlNifMutex erl_nif_mutex_t;

typedef char cstr;
typedef int32_t i32;
#define null NULL

static magic_t magic_cookie = null;
static erl_nif_mutex_t *magic_mutex = null;

static erl_nif_term_t make_error(erl_nif_env_t *env, const cstr *message) {
  return enif_make_tuple2(env, enif_make_atom(env, "error"),
                          enif_make_string(env, message, ERL_NIF_LATIN1));
}

static erl_nif_term_t make_ok(erl_nif_env_t *env, const cstr *body) {
  return enif_make_tuple2(env, enif_make_atom(env, "ok"),
                          enif_make_string(env, body, ERL_NIF_LATIN1));
}

static int load(erl_nif_env_t *env, void **priv_data,
                erl_nif_term_t load_info) {
  magic_mutex = enif_mutex_create("magic_mutex");
  if (!magic_mutex) {
    fprintf(stderr, "magic: Error: enif_mutex_create failed\n");
    return 1;
  }

  magic_cookie = magic_open(MAGIC_MIME_TYPE);
  if (!magic_cookie) {
    fprintf(stderr, "magic: Error: magic_open failed\n");

    enif_mutex_destroy(magic_mutex);
    magic_mutex = null;
    return 1;
  }

  if (magic_load(magic_cookie, null) != 0) {
    fprintf(stderr, "magic: Error: magic_load failed\n");

    magic_close(magic_cookie);
    enif_mutex_destroy(magic_mutex);

    magic_cookie = null;
    magic_mutex = null;
    return 1;
  }

  return 0;
}

static void unload(erl_nif_env_t *env, void *priv_data) {
  if (magic_cookie) {
    magic_close(magic_cookie);
    magic_cookie = null;
  }

  if (magic_mutex) {
    enif_mutex_destroy(magic_mutex);
    magic_mutex = null;
  }
}

static erl_nif_term_t get_mime_type_nif(erl_nif_env_t *env, i32 argc,
                                        const erl_nif_term_t argv[]) {
  if (argc != 1) {
    fprintf(stderr, "magic: Error: wrong number of arguments\n");
    return enif_make_badarg(env);
  }

  cstr file_path[1024] = {0};
  if (!enif_get_string(env, argv[0], file_path, sizeof(file_path),
                       ERL_NIF_LATIN1)) {
    fprintf(
        stderr,
        "magic: Error: couldn't get file path, are you passing a string?\n");
    return enif_make_badarg(env);
  }

  enif_mutex_lock(magic_mutex);
  const cstr *mime_type = magic_file(magic_cookie, file_path);
  erl_nif_term_t result;
  if (!mime_type) {
    const cstr *error_message = magic_error(magic_cookie);
    result = make_error(env, error_message);
  } else {
    result = make_ok(env, mime_type);
  }

  enif_mutex_unlock(magic_mutex);
  return result;
}

static erl_nif_func_t nif_funcs[1] = {
    {"get_mime_type", 1, get_mime_type_nif, ERL_NIF_DIRTY_JOB_IO_BOUND},
};

ERL_NIF_INIT(errm_http_magic_nif, nif_funcs, load, null, null, unload);
