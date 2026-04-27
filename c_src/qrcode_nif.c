/*
 * Image.QRCode NIF — encode/decode QR codes via nayuki/QR-Code-generator
 * (encoder, MIT) and dlbeer/quirc (decoder, ISC). License headers retained
 * in the vendored sources under c_src/nayuki and c_src/quirc.
 */

#include <erl_nif.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "nayuki/qrcodegen.h"
#include "quirc/quirc.h"

static ERL_NIF_TERM atom_ok;
static ERL_NIF_TERM atom_error;
static ERL_NIF_TERM atom_encode_failed;
static ERL_NIF_TERM atom_alloc_failed;
static ERL_NIF_TERM atom_invalid_size;
static ERL_NIF_TERM atom_payload;
static ERL_NIF_TERM atom_version;
static ERL_NIF_TERM atom_ecc_level;
static ERL_NIF_TERM atom_mask;
static ERL_NIF_TERM atom_data_type;
static ERL_NIF_TERM atom_eci;
static ERL_NIF_TERM atom_corners;

static int
load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info)
{
	(void)priv_data;
	(void)load_info;
	atom_ok            = enif_make_atom(env, "ok");
	atom_error         = enif_make_atom(env, "error");
	atom_encode_failed = enif_make_atom(env, "encode_failed");
	atom_alloc_failed  = enif_make_atom(env, "alloc_failed");
	atom_invalid_size  = enif_make_atom(env, "invalid_size");
	atom_payload       = enif_make_atom(env, "payload");
	atom_version       = enif_make_atom(env, "version");
	atom_ecc_level     = enif_make_atom(env, "ecc_level");
	atom_mask          = enif_make_atom(env, "mask");
	atom_data_type     = enif_make_atom(env, "data_type");
	atom_eci           = enif_make_atom(env, "eci");
	atom_corners       = enif_make_atom(env, "corners");
	return 0;
}

static ERL_NIF_TERM
make_error(ErlNifEnv *env, ERL_NIF_TERM reason)
{
	return enif_make_tuple2(env, atom_error, reason);
}

/* encode(text, ecc, version_min, version_max, mask, boost_ecc)
 *   text         : binary (UTF-8, NUL-terminated copy made internally)
 *   ecc          : 0=LOW 1=MEDIUM 2=QUARTILE 3=HIGH
 *   version_min  : 1..40
 *   version_max  : 1..40
 *   mask         : -1 (auto) | 0..7
 *   boost_ecc    : 0 | 1
 *
 * Returns {:ok, size, modules} where modules is a (size*size) byte binary
 * with 0 = light module, 1 = dark module, row-major.
 */
static ERL_NIF_TERM
encode_nif(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
	(void)argc;
	ErlNifBinary text_bin;
	int ecc, version_min, version_max, mask, boost_ecc;

	if (!enif_inspect_binary(env, argv[0], &text_bin) ||
	    !enif_get_int(env, argv[1], &ecc) ||
	    !enif_get_int(env, argv[2], &version_min) ||
	    !enif_get_int(env, argv[3], &version_max) ||
	    !enif_get_int(env, argv[4], &mask) ||
	    !enif_get_int(env, argv[5], &boost_ecc)) {
		return enif_make_badarg(env);
	}

	/* nayuki expects a NUL-terminated C string. */
	char *text = (char *)enif_alloc(text_bin.size + 1);
	if (!text)
		return make_error(env, atom_alloc_failed);
	memcpy(text, text_bin.data, text_bin.size);
	text[text_bin.size] = '\0';

	uint8_t *qrcode = (uint8_t *)enif_alloc(qrcodegen_BUFFER_LEN_MAX);
	uint8_t *tmp    = (uint8_t *)enif_alloc(qrcodegen_BUFFER_LEN_MAX);
	if (!qrcode || !tmp) {
		enif_free(text);
		if (qrcode) enif_free(qrcode);
		if (tmp)    enif_free(tmp);
		return make_error(env, atom_alloc_failed);
	}

	bool ok = qrcodegen_encodeText(
		text, tmp, qrcode,
		(enum qrcodegen_Ecc)ecc,
		version_min, version_max,
		(enum qrcodegen_Mask)mask,
		boost_ecc ? true : false);

	enif_free(text);
	enif_free(tmp);

	if (!ok) {
		enif_free(qrcode);
		return make_error(env, atom_encode_failed);
	}

	int size = qrcodegen_getSize(qrcode);
	if (size <= 0) {
		enif_free(qrcode);
		return make_error(env, atom_encode_failed);
	}

	ErlNifBinary modules;
	if (!enif_alloc_binary((size_t)size * (size_t)size, &modules)) {
		enif_free(qrcode);
		return make_error(env, atom_alloc_failed);
	}

	uint8_t *out = modules.data;
	for (int y = 0; y < size; y++) {
		for (int x = 0; x < size; x++) {
			*out++ = qrcodegen_getModule(qrcode, x, y) ? 1 : 0;
		}
	}

	enif_free(qrcode);

	return enif_make_tuple3(env, atom_ok,
		enif_make_int(env, size),
		enif_make_binary(env, &modules));
}

/* decode(grayscale, width, height)
 *   grayscale : binary of width*height bytes (8-bit luminance)
 *   width     : positive int
 *   height    : positive int
 *
 * Returns {:ok, [%{payload, version, ecc_level, mask, data_type, eci, corners}]}
 * where corners is a 4-tuple of {x, y} pairs (TL, TR, BR, BL).
 */
static ERL_NIF_TERM
decode_nif(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
	(void)argc;
	ErlNifBinary gray;
	int width, height;

	if (!enif_inspect_binary(env, argv[0], &gray) ||
	    !enif_get_int(env, argv[1], &width) ||
	    !enif_get_int(env, argv[2], &height)) {
		return enif_make_badarg(env);
	}
	if (width <= 0 || height <= 0 ||
	    gray.size != (size_t)width * (size_t)height) {
		return make_error(env, atom_invalid_size);
	}

	struct quirc *q = quirc_new();
	if (!q)
		return make_error(env, atom_alloc_failed);

	if (quirc_resize(q, width, height) < 0) {
		quirc_destroy(q);
		return make_error(env, atom_alloc_failed);
	}

	int qw, qh;
	uint8_t *buf = quirc_begin(q, &qw, &qh);
	memcpy(buf, gray.data, gray.size);
	quirc_end(q);

	int count = quirc_count(q);
	ERL_NIF_TERM list = enif_make_list(env, 0);

	for (int i = count - 1; i >= 0; i--) {
		struct quirc_code code;
		struct quirc_data data;
		quirc_extract(q, i, &code);

		if (quirc_decode(&code, &data) != QUIRC_SUCCESS) {
			quirc_flip(&code);
			if (quirc_decode(&code, &data) != QUIRC_SUCCESS)
				continue;
		}

		ErlNifBinary payload;
		if (!enif_alloc_binary((size_t)data.payload_len, &payload)) {
			quirc_destroy(q);
			return make_error(env, atom_alloc_failed);
		}
		memcpy(payload.data, data.payload, (size_t)data.payload_len);

		ERL_NIF_TERM corners = enif_make_tuple4(env,
			enif_make_tuple2(env,
				enif_make_int(env, code.corners[0].x),
				enif_make_int(env, code.corners[0].y)),
			enif_make_tuple2(env,
				enif_make_int(env, code.corners[1].x),
				enif_make_int(env, code.corners[1].y)),
			enif_make_tuple2(env,
				enif_make_int(env, code.corners[2].x),
				enif_make_int(env, code.corners[2].y)),
			enif_make_tuple2(env,
				enif_make_int(env, code.corners[3].x),
				enif_make_int(env, code.corners[3].y)));

		ERL_NIF_TERM map = enif_make_new_map(env);
		enif_make_map_put(env, map, atom_payload,   enif_make_binary(env, &payload), &map);
		enif_make_map_put(env, map, atom_version,   enif_make_int(env, data.version), &map);
		enif_make_map_put(env, map, atom_ecc_level, enif_make_int(env, data.ecc_level), &map);
		enif_make_map_put(env, map, atom_mask,      enif_make_int(env, data.mask), &map);
		enif_make_map_put(env, map, atom_data_type, enif_make_int(env, data.data_type), &map);
		enif_make_map_put(env, map, atom_eci,       enif_make_uint(env, data.eci), &map);
		enif_make_map_put(env, map, atom_corners,   corners, &map);

		list = enif_make_list_cell(env, map, list);
	}

	quirc_destroy(q);
	return enif_make_tuple2(env, atom_ok, list);
}

static ErlNifFunc nif_funcs[] = {
	{"encode", 6, encode_nif, ERL_NIF_DIRTY_JOB_CPU_BOUND},
	{"decode", 3, decode_nif, ERL_NIF_DIRTY_JOB_CPU_BOUND},
};

ERL_NIF_INIT(Elixir.Image.QRCode.Nif, nif_funcs, load, NULL, NULL, NULL)
