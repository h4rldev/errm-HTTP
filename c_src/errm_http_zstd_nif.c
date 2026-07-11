#include <erl_nif.h>
#include <stdint.h>
#include <stdio.h>
#include <zstd.h>

typedef ERL_NIF_TERM erl_nif_term_t;
typedef ErlNifEnv erl_nif_env_t;
typedef ErlNifBinary erl_nif_binary_t;
typedef ErlNifFunc erl_nif_func_t;
typedef ErlNifMutex erl_nif_mutex_t;

typedef char cstr;
typedef int32_t i32;
typedef uint8_t u8;
typedef uint64_t u64;
#define null NULL

static erl_nif_term_t make_error(erl_nif_env_t *env, const cstr *message) {
  return enif_make_tuple2(env, enif_make_atom(env, "error"),
                          enif_make_string(env, message, ERL_NIF_LATIN1));
}

static erl_nif_term_t nif_compress(erl_nif_env_t *env, i32 argc,
                                   const erl_nif_term_t argv[]) {
  if (argc != 2) {
    fprintf(stderr,
            "errm_http_zstd_nif: compress: arity error, expected 2, got %d\n",
            argc);
    return enif_make_badarg(env);
  }

  erl_nif_binary_t input, output;
  i32 level;

  if (!enif_inspect_binary(env, argv[0], &input)) {
    fprintf(stderr, "errm_http_zstd_nif: compress: input is not a binary\n");
    return enif_make_badarg(env);
  }

  if (!enif_get_int(env, argv[1], &level)) {
    fprintf(stderr, "errm_http_zstd_nif: compress: level is not an integer\n");
    return enif_make_badarg(env);
  }

  i32 max_level = ZSTD_maxCLevel();
  if (level < 0)
    level = 0;
  if (level > max_level)
    level = max_level;

  u64 out_cap = ZSTD_compressBound(input.size);
  u8 *out = enif_alloc(out_cap);
  if (!out)
    return make_error(env, "errm_http_zstd_nif: compress: out of memory");

  u64 compressed_size =
      ZSTD_compress(out, out_cap, input.data, input.size, level);
  if (ZSTD_isError(compressed_size)) {
    enif_free(out);
    static cstr error_message[1024];
    snprintf(error_message, sizeof(error_message),
             "errm_http_zstd_nif: compress: ZSTD_compress failed: %s",
             ZSTD_getErrorName(compressed_size));
    return make_error(env, error_message);
  }

  if (!enif_alloc_binary(compressed_size, &output)) {
    enif_free(out);
    return make_error(env,
                      "errm_http_zstd_nif: compress: binary allocation failed");
  }

  memcpy(output.data, out, compressed_size);
  enif_free(out);

  return enif_make_tuple2(env, enif_make_atom(env, "ok"),
                          enif_make_binary(env, &output));
}

static erl_nif_term_t nif_decompress(erl_nif_env_t *env, i32 argc,
                                     const erl_nif_term_t argv[]) {
  if (argc != 1) {
    fprintf(stderr,
            "errm_http_zstd_nif: decompress: arity error, expected 1, got %d\n",
            argc);
    return enif_make_badarg(env);
  }

  erl_nif_binary_t input, output;
  if (!enif_inspect_binary(env, argv[0], &input)) {
    fprintf(stderr, "errm_http_zstd_nif: decompress: input is not a binary\n");
    return enif_make_badarg(env);
  }

  u64 decompress_size = ZSTD_getFrameContentSize(input.data, input.size);
  if (decompress_size == ZSTD_CONTENTSIZE_ERROR ||
      decompress_size == ZSTD_CONTENTSIZE_UNKNOWN)
    return make_error(env,
                      "errm_http_zstd_nif: decompress: invalid zstd frame");

  u8 *out = enif_alloc(decompress_size);
  if (!out)
    return make_error(env, "errm_http_zstd_nif: decompress: out of memory");

  u64 result_size =
      ZSTD_decompress(out, decompress_size, input.data, input.size);
  if (ZSTD_isError(result_size)) {
    enif_free(out);
    static cstr error_message[1024];
    snprintf(error_message, sizeof(error_message),
             "errm_http_zstd_nif: decompress: ZSTD_decompress failed: %s",
             ZSTD_getErrorName(result_size));
    return make_error(env, error_message);
  }

  if (!enif_alloc_binary(result_size, &output)) {
    enif_free(out);
    return make_error(
        env, "errm_http_zstd_nif: decompress: binary allocation failed");
  }

  memcpy(output.data, out, result_size);
  enif_free(out);

  return enif_make_tuple2(env, enif_make_atom(env, "ok"),
                          enif_make_binary(env, &output));
}

erl_nif_func_t nif_funcs[2] = {
    {"compress", 2, nif_compress, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"decompress", 1, nif_decompress, ERL_NIF_DIRTY_JOB_CPU_BOUND},
};

ERL_NIF_INIT(errm_http_zstd_nif, nif_funcs, NULL, NULL, NULL, NULL)
