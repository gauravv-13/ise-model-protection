#!/usr/bin/env python3
"""Train the three int8 workloads on MNIST and export them as plain model blobs.

    cnn    tiny CNN  (2 x conv5x5+pool, 2 x FC)   about 12 KB of weights
    mlp_s  MLP 784-128-10                         about 100 KB
    mlp_l  MLP 784-1024-256-10                    about 1 MB

Plain numpy (no PyTorch on the workstation). Training is float; weights are
then quantized to int8 with power-of-two scales, so inference needs only
integer multiply-adds and shifts (see `infer_int`, mirrored by sw/loader/nn.c).

Outputs in build/models/: <name>.bin (model blob), <name>_vec.bin (test images
and expected logits), and models.json (sizes and accuracy).

    python3 models/train.py [--data ~/ise-data/mnist] [--out build/models]
"""
import argparse
import gzip
import json
import os
import struct

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

MAGIC = 0x314D4E4E      # 'NNM1'
FC, CONV = 0, 1
N_VEC = 64              # test images exported for the on-target check

MODELS = {
    "cnn":   [("conv", 8, 5), ("conv", 16, 5), ("fc", 32), ("fc", 10)],
    "mlp_s": [("fc", 128), ("fc", 10)],
    "mlp_l": [("fc", 1024), ("fc", 256), ("fc", 10)],
}
EPOCHS = {"cnn": 4, "mlp_s": 8, "mlp_l": 6}


def load_mnist(folder):
    def read(name, offset):
        with gzip.open(os.path.join(folder, name)) as fh:
            return np.frombuffer(fh.read(), np.uint8, offset=offset)
    xtr = read("train-images-idx3-ubyte.gz", 16).reshape(-1, 1, 28, 28)
    ytr = read("train-labels-idx1-ubyte.gz", 8)
    xte = read("t10k-images-idx3-ubyte.gz", 16).reshape(-1, 1, 28, 28)
    yte = read("t10k-labels-idx1-ubyte.gz", 8)
    return xtr, ytr, xte, yte


# ----------------------------------------------------------------------------
# Float training
# ----------------------------------------------------------------------------
def init_params(spec, rng):
    params, c, hw = [], 1, 28
    for layer in spec:
        if layer[0] == "conv":
            _, oc, k = layer
            w = rng.standard_normal((oc, c, k, k)).astype(np.float32) * np.sqrt(2.0 / (c * k * k))
            c, hw = oc, (hw - k + 1) // 2
        else:
            n_in = c * hw * hw
            w = rng.standard_normal((layer[1], n_in)).astype(np.float32) * np.sqrt(2.0 / n_in)
            c, hw = layer[1], 1
        params.append([w, np.zeros(w.shape[0], np.float32)])
    return params


def conv_cols(x, k):
    """x: N,C,H,W -> N,H',W',C*k*k (valid convolution patches)."""
    win = sliding_window_view(x, (k, k), axis=(2, 3))          # N,C,H',W',k,k
    n, c, h, w = win.shape[:4]
    return win.transpose(0, 2, 3, 1, 4, 5).reshape(n, h, w, c * k * k)


def forward(params, spec, x, cache=None):
    """Float forward pass. Returns logits; fills `cache` for backprop if given."""
    a = x
    for i, ((w, b), layer) in enumerate(zip(params, spec)):
        last = i == len(spec) - 1
        if layer[0] == "conv":
            k = layer[2]
            cols = conv_cols(a, k)
            z = (cols @ w.reshape(w.shape[0], -1).T + b).transpose(0, 3, 1, 2)   # N,OC,H',W'
            r = np.maximum(z, 0)
            n, oc, h, wd = r.shape
            pooled = r.reshape(n, oc, h // 2, 2, wd // 2, 2)
            out = pooled.max(axis=(3, 5))
            if cache is not None:
                cache.append((a, cols, z, pooled, out))
            a = out
        else:
            flat = a.reshape(a.shape[0], -1)
            z = flat @ w.T + b
            out = z if last else np.maximum(z, 0)
            if cache is not None:
                cache.append((a, flat, z))
            a = out
    return a


def backward(params, spec, cache, dlogits):
    grads, d = [None] * len(spec), dlogits
    for i in reversed(range(len(spec))):
        w, _ = params[i]
        if spec[i][0] == "fc":
            a_in, flat, z = cache[i]
            if i != len(spec) - 1:
                d = d * (z > 0)
            grads[i] = (d.T @ flat, d.sum(0))
            d = (d @ w).reshape(a_in.shape)
        else:
            a_in, cols, z, pooled, out = cache[i]
            k = spec[i][2]
            n, oc, h, wd = z.shape
            mask = pooled == out[:, :, :, None, :, None]            # route to the max
            dz = (mask * d[:, :, :, None, :, None]).reshape(n, oc, h, wd) * (z > 0)
            dzf = dz.transpose(0, 2, 3, 1).reshape(-1, oc)
            grads[i] = (dzf.T @ cols.reshape(-1, cols.shape[-1]), dzf.sum(0))
            if i > 0:                                                # gradient w.r.t. the input
                dcols = (dzf @ w.reshape(oc, -1)).reshape(n, h, wd, a_in.shape[1], k, k)
                dx = np.zeros_like(a_in, dtype=np.float32)
                for u in range(k):
                    for v in range(k):
                        dx[:, :, u:u + h, v:v + wd] += dcols[:, :, :, :, u, v].transpose(0, 3, 1, 2)
                d = dx
    return [(gw.reshape(params[i][0].shape), gb) for i, (gw, gb) in enumerate(grads)]


def train(name, spec, xtr, ytr, rng):
    params = init_params(spec, rng)
    m = [[np.zeros_like(w), np.zeros_like(b)] for w, b in params]
    v = [[np.zeros_like(w), np.zeros_like(b)] for w, b in params]
    lr, b1, b2, step, batch = 1e-3, 0.9, 0.999, 0, 128
    x = xtr.astype(np.float32) / 256.0
    for epoch in range(EPOCHS[name]):
        order = rng.permutation(len(x))
        loss_sum = 0.0
        for s in range(0, len(x), batch):
            idx = order[s:s + batch]
            cache = []
            logits = forward(params, spec, x[idx], cache)
            logits -= logits.max(1, keepdims=True)
            p = np.exp(logits); p /= p.sum(1, keepdims=True)
            loss_sum += -np.log(p[np.arange(len(idx)), ytr[idx]] + 1e-12).sum()
            p[np.arange(len(idx)), ytr[idx]] -= 1
            grads = backward(params, spec, cache, p / len(idx))
            step += 1
            for i, g in enumerate(grads):
                for j in range(2):
                    m[i][j] = b1 * m[i][j] + (1 - b1) * g[j]
                    v[i][j] = b2 * v[i][j] + (1 - b2) * g[j] ** 2
                    params[i][j] -= lr * (m[i][j] / (1 - b1 ** step)) / (np.sqrt(v[i][j] / (1 - b2 ** step)) + 1e-8)
        print(f"  {name} epoch {epoch + 1}/{EPOCHS[name]} loss {loss_sum / len(x):.4f}", flush=True)
    return params


def predict_float(params, spec, x):
    out = [forward(params, spec, x[s:s + 1000].astype(np.float32) / 256.0).argmax(1)
           for s in range(0, len(x), 1000)]
    return np.concatenate(out)


# ----------------------------------------------------------------------------
# Quantization to int8 and integer inference
# ----------------------------------------------------------------------------
def quantize(params, spec, calib):
    """Power-of-two scales. Activations are uint8 with `fa` fraction bits
    (input pixels: fa = 8), weights int8 with `fw` fraction bits per layer."""
    layers, fa = [], 8
    a = calib.astype(np.float32) / 256.0
    for i, ((w, b), layer) in enumerate(zip(params, spec)):
        last = i == len(spec) - 1
        fw = int(np.floor(np.log2(127.0 / np.abs(w).max())))
        wq = np.clip(np.round(w * 2.0 ** fw), -127, 127).astype(np.int8)
        bq = np.round(b * 2.0 ** (fa + fw)).astype(np.int64)
        a = forward([[w, b]], [layer], a)                    # float output of this layer
        if not last:
            a = np.maximum(a, 0)                             # (forward of one layer skips its ReLU)
            fa_out = int(np.floor(np.log2(255.0 / np.percentile(a, 99.9))))
            shift = fa + fw - fa_out
            assert shift >= 0
        else:
            fa_out, shift = fa + fw, 0
        layers.append({"type": CONV if layer[0] == "conv" else FC, "w": wq, "b": bq.astype(np.int32),
                       "k": layer[2] if layer[0] == "conv" else 0, "shift": shift, "relu": int(not last)})
        assert np.abs(bq).max() < 2 ** 31
        fa = fa_out
    return layers


def infer_int(layers, x):
    """Bit-exact integer inference. x: N,1,28,28 uint8. Returns int32 logits."""
    a = x.astype(np.int64)
    for layer in layers:
        w, b = layer["w"].astype(np.int64), layer["b"].astype(np.int64)
        if layer["type"] == CONV:
            cols = conv_cols(a, layer["k"])
            acc = (cols @ w.reshape(w.shape[0], -1).T + b).transpose(0, 3, 1, 2)
        else:
            acc = a.reshape(a.shape[0], -1) @ w.T + b
        assert np.abs(acc).max() < 2 ** 31                    # the target uses 32-bit sums
        if layer["relu"]:
            acc = np.clip(acc >> layer["shift"], 0, 255)
        if layer["type"] == CONV:                              # 2x2 max pooling
            n, c, h, wd = acc.shape
            acc = acc.reshape(n, c, h // 2, 2, wd // 2, 2).max(axis=(3, 5))
        a = acc
    return a.astype(np.int32)


def export_blob(layers):
    """Header, layer descriptors (weights, layer shapes and scales are all
    part of the protected model), then weights and biases."""
    def pad8(b):
        return b + bytes(-len(b) % 8)
    head_len = 16 + 32 * len(layers)
    body, descs = b"", []
    for layer in layers:
        w = layer["w"]
        w_off = head_len + len(body); body += pad8(w.tobytes())
        b_off = head_len + len(body); body += pad8(layer["b"].tobytes())
        in_n = w.shape[1]
        descs.append(struct.pack("<8I", layer["type"], in_n, w.shape[0], layer["k"], layer["shift"],
                                 layer["relu"], w_off, b_off))
    return struct.pack("<4I", MAGIC, len(layers), 1, 28) + b"".join(descs) + body


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=os.path.expanduser("~/ise-data/mnist"))
    ap.add_argument("--out", default="build/models")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    xtr, ytr, xte, yte = load_mnist(args.data)
    summary = {}
    for name, spec in MODELS.items():
        rng = np.random.default_rng(2026)
        print(f"training {name}", flush=True)
        params = train(name, spec, xtr, ytr, rng)
        acc_float = float((predict_float(params, spec, xte) == yte).mean())
        layers = quantize(params, spec, xtr[:2000])
        logits = np.concatenate([infer_int(layers, xte[s:s + 1000]) for s in range(0, len(xte), 1000)])
        acc_int = float((logits.argmax(1) == yte).mean())
        blob = export_blob(layers)
        with open(os.path.join(args.out, f"{name}.bin"), "wb") as fh:
            fh.write(blob)
        # Test vectors: N_VEC images (784 bytes each), their labels, expected logits.
        with open(os.path.join(args.out, f"{name}_vec.bin"), "wb") as fh:
            fh.write(xte[:N_VEC].tobytes() + yte[:N_VEC].tobytes() + logits[:N_VEC].astype("<i4").tobytes())
        weights = sum(l["w"].size for l in layers)
        summary[name] = {"layers": [list(l) for l in spec], "weight_bytes": weights, "blob_bytes": len(blob),
                         "acc_float": acc_float, "acc_int8": acc_int,
                         "acc_int8_first_vectors": float((logits[:N_VEC].argmax(1) == yte[:N_VEC]).mean())}
        print(f"  {name}: {weights} weight bytes, blob {len(blob)} B, "
              f"accuracy float {acc_float:.4f}, int8 {acc_int:.4f}", flush=True)
    with open(os.path.join(args.out, "models.json"), "w") as fh:
        json.dump(summary, fh, indent=2)


if __name__ == "__main__":
    main()
