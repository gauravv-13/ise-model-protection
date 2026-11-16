// int8 inference on a plain model blob (format: models/train.py, export_blob).
// Mirrors infer_int() there bit for bit. In the SoC this is the cluster's job;
// here CVA6 runs it to show the loaded model still gives the same outputs.
#include "platform.h"

#define NN_MAGIC 0x314D4E4Eu
enum { FC = 0, CONV = 1 };
typedef struct { uint32_t type, in_n, out_n, k, shift, relu, w_off, b_off; } layer_t;

#define BUF_BYTES 4608                    // largest activation: 8 x 24 x 24
static uint8_t  buf_a[BUF_BYTES], buf_b[BUF_BYTES], buf_c[BUF_BYTES];
static int32_t  out_raw[16];

static inline uint8_t act(int32_t acc, uint32_t shift) {
    acc >>= shift;
    return acc < 0 ? 0 : acc > 255 ? 255 : (uint8_t)acc;
}

int nn_infer(const uint8_t *blob, const uint8_t *image, int32_t logits[10]) {
    const uint32_t *head = (const uint32_t *)blob;
    const layer_t *layers = (const layer_t *)(blob + 16);
    if (head[0] != NN_MAGIC) return -1;
    const uint8_t *in = image;
    uint8_t *out = buf_a;
    uint32_t hw = head[3];                               // current feature-map side

    for (uint32_t l = 0; l < head[1]; l++) {
        const layer_t *ly = &layers[l];
        const int8_t  *w = (const int8_t *)(blob + ly->w_off);
        const int32_t *b = (const int32_t *)(blob + ly->b_off);
        if (ly->type == CONV) {                          // k x k valid conv, ReLU, 2x2 max pool
            uint32_t k = ly->k, oh = hw - k + 1;
            for (uint32_t o = 0; o < ly->out_n; o++)
                for (uint32_t y = 0; y < oh; y++)
                    for (uint32_t x = 0; x < oh; x++) {
                        int32_t acc = b[o];
                        for (uint32_t c = 0; c < ly->in_n; c++)
                            for (uint32_t u = 0; u < k; u++) {
                                const int8_t  *wp = w + ((o * ly->in_n + c) * k + u) * k;
                                const uint8_t *ip = in + (c * hw + y + u) * hw + x;
                                for (uint32_t v = 0; v < k; v++) acc += wp[v] * ip[v];
                            }
                        buf_c[(o * oh + y) * oh + x] = act(acc, ly->shift);
                    }
            uint32_t ph = oh / 2;
            for (uint32_t o = 0; o < ly->out_n; o++)
                for (uint32_t y = 0; y < ph; y++)
                    for (uint32_t x = 0; x < ph; x++) {
                        const uint8_t *p = buf_c + (o * oh + 2 * y) * oh + 2 * x;
                        uint8_t m = p[0];
                        if (p[1] > m) m = p[1];
                        if (p[oh] > m) m = p[oh];
                        if (p[oh + 1] > m) m = p[oh + 1];
                        out[(o * ph + y) * ph + x] = m;
                    }
            hw = ph;
        } else {                                         // fully connected
            for (uint32_t o = 0; o < ly->out_n; o++) {
                int32_t acc = b[o];
                const int8_t *wp = w + o * ly->in_n;
                for (uint32_t i = 0; i < ly->in_n; i++) acc += wp[i] * in[i];
                if (ly->relu) out[o] = act(acc, ly->shift);
                else          out_raw[o] = acc;
            }
        }
        in  = out;
        out = (out == buf_a) ? buf_b : buf_a;
    }
    int best = 0;
    for (int i = 0; i < 10; i++) {
        logits[i] = out_raw[i];
        if (out_raw[i] > out_raw[best]) best = i;
    }
    return best;
}
