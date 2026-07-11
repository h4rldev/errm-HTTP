#include <brotli/decode.h>
#include <brotli/encode.h>
#include <erl_nif.h>
#include <stdint.h>
#include <stdio.h>

typedef ERL_NIF_TERM erl_nif_term_t;
typedef ErlNifEnv erl_nif_env_t;
typedef ErlNifBinary erl_nif_binary_t;
typedef ErlNifFunc erl_nif_func_t;
typedef ErlNifMutex erl_nif_mutex_t;

typedef BrotliEncoderState br_enc_state_t;
typedef BrotliEncoderOperation br_enc_op_t;
typedef BrotliDecoderState br_dec_state_t;
typedef BrotliDecoderResult br_dec_result_t;

typedef char cstr;
typedef int32_t i32;
typedef uint8_t u8;
typedef uint32_t u32;
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
            "errm_http_brotli_nif: compress: arity error, expected 2, got %d\n",
            argc);
    return enif_make_badarg(env);
  }

  erl_nif_binary_t input, output;
  i32 level;

  if (!enif_inspect_binary(env, argv[0], &input)) {
    fprintf(stderr, "errm_http_brotli_nif: compress: input is not a binary\n");
    return enif_make_badarg(env);
  }

  if (!enif_get_int(env, argv[1], &level)) {
    fprintf(stderr,
            "errm_http_brotli_nif: compress: level is not an integer\n");
    return enif_make_badarg(env);
  }

  if (level < 0)
    level = 0;
  if (level > BROTLI_MAX_QUALITY)
    level = BROTLI_MAX_QUALITY;

  u64 max_compressed_size = input.size + (input.size >> 11) + 16;
  if (max_compressed_size < 256)
    max_compressed_size = 256;

  u8 *out = enif_alloc(max_compressed_size);
  if (!out)
    return make_error(env, "errm_http_brotli_nif: compress: out of memory");

  u64 out_size = max_compressed_size;

  br_enc_state_t *state = BrotliEncoderCreateInstance(null, null, null);
  if (!state) {
    enif_free(out);
    return make_error(
        env, "errm_http_brotli_nif: compress: failed to create brotli encoder");
  }

  if (BrotliEncoderSetParameter(state, BROTLI_PARAM_QUALITY, (u32)level) !=
      BROTLI_TRUE) {
    enif_free(out);
    return make_error(env, "errm_http_brotli_nif: compress: invalid level");
  }

  br_enc_op_t op = BROTLI_OPERATION_FINISH;
  const u8 *next_in = input.data;
  u64 available_in = input.size;
  u8 *next_out = out;
  u64 available_out = out_size;

  if (!BrotliEncoderCompressStream(state, op, &available_in, &next_in,
                                   &available_out, &next_out, null)) {
    BrotliEncoderDestroyInstance(state);
    enif_free(out);
    return make_error(env,
                      "errm_http_brotli_nif: compress: failed to compress");
  }

  u64 compressed_size = out_size - available_out;
  BrotliEncoderDestroyInstance(state);

  if (!enif_alloc_binary(compressed_size, &output)) {
    enif_free(out);
    return make_error(
        env, "errm_http_brotli_nif: compress: binary allocation failed");
  }

  memcpy(output.data, out, compressed_size);
  enif_free(out);

  return enif_make_tuple2(env, enif_make_atom(env, "ok"),
                          enif_make_binary(env, &output));
}

static erl_nif_term_t nif_decompress(erl_nif_env_t *env, i32 argc,
                                     const erl_nif_term_t argv[]) {
  if (argc != 1) {
    fprintf(
        stderr,
        "errm_http_brotli_nif: decompress: arity error, expected 1, got %d\n",
        argc);
    return enif_make_badarg(env);
  }

  erl_nif_binary_t input, output;
  if (!enif_inspect_binary(env, argv[0], &input)) {
    fprintf(stderr,
            "errm_http_brotli_nif: decompress: input is not a binary\n");
    return enif_make_badarg(env);
  }

  u64 out_size = 4096;
  u8 *out = enif_alloc(out_size);
  if (!out)
    return make_error(env, "errm_http_brotli_nif: decompress: out of memory");

  br_dec_state_t *state = BrotliDecoderCreateInstance(null, null, null);
  if (!state) {
    enif_free(out);
    return make_error(
        env,
        "errm_http_brotli_nif: decompress: failed to create brotli decoder");
  }

  const u8 *next_in = input.data;
  u64 available_in = input.size;
  u64 available_out = out_size;
  u8 *next_out = out;

  br_dec_result_t res;

  for (;;) {
    next_out = out + (out_size - available_out);
    available_out = out_size - available_out;
    res = BrotliDecoderDecompressStream(state, &available_in, &next_in,
                                        &available_out, &next_out, null);

    if (res == BROTLI_DECODER_RESULT_ERROR) {
      BrotliDecoderDestroyInstance(state);
      enif_free(out);
      return make_error(
          env, "errm_http_brotli_nif: decompress: brotli decompression failed");
    }

    if (res == BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT) {
      u64 new_size = out_size * 2;
      u8 *new_out = enif_realloc(out, new_size);
      if (!new_out) {
        BrotliDecoderDestroyInstance(state);
        enif_free(out);
        return make_error(env,
                          "errm_http_brotli_nif: decompress: out of memory");
      }

      out = new_out;
      out_size = new_size;
      continue;
    }

    break;
  }

  if (res != BROTLI_DECODER_RESULT_SUCCESS) {
    BrotliDecoderDestroyInstance(state);
    enif_free(out);
    return make_error(
        env,
        "errm_http_brotli_nif: decompress: brotli decompression incomplete");
  }

  u64 final_size = out_size - available_out;
  BrotliDecoderDestroyInstance(state);

  if (!enif_alloc_binary(final_size, &output)) {
    enif_free(out);
    return make_error(
        env, "errm_http_brotli_nif: decompress: binary allocation failed");
  }

  memcpy(output.data, out, final_size);
  enif_free(out);

  return enif_make_tuple2(env, enif_make_atom(env, "ok"),
                          enif_make_binary(env, &output));
}

static erl_nif_func_t nif_funcs[2] = {
    {"compress", 2, nif_compress, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"decompress", 1, nif_decompress, ERL_NIF_DIRTY_JOB_CPU_BOUND},
};

ERL_NIF_INIT(errm_http_brotli_nif, nif_funcs, NULL, NULL, NULL, NULL)
