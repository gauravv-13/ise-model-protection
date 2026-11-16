"""AES-128 reference in plain Python: block encryption, CTR and CMAC.

Only used to build and check model images on the host; speed does not matter.
`python3 tools/aes_ref.py` runs the standard test vectors (FIPS-197,
SP 800-38A CTR, RFC 4493 CMAC).
"""

SBOX = []


def _init_sbox():
    # S-box from the multiplicative inverse in GF(2^8) plus the affine map.
    p = q = 1
    box = [0] * 256
    while True:
        p = p ^ ((p << 1) & 0xFF) ^ (0x1B if p & 0x80 else 0)      # p *= 3
        q ^= q << 1; q ^= q << 2; q ^= q << 4; q &= 0xFF            # q /= 3
        if q & 0x80:
            q ^= 0x09
        x = q ^ (q << 1 | q >> 7) ^ (q << 2 | q >> 6) ^ (q << 3 | q >> 5) ^ (q << 4 | q >> 4)
        box[p] = (x ^ 0x63) & 0xFF
        if p == 1:
            break
    box[0] = 0x63
    return box


SBOX = _init_sbox()
XT = [((x << 1) ^ (0x1B if x & 0x80 else 0)) & 0xFF for x in range(256)]


def expand_key(key):
    """16-byte key -> 11 round keys (each 16 bytes)."""
    w = list(key)
    rcon = 1
    for i in range(16, 176, 4):
        t = w[i - 4:i]
        if i % 16 == 0:
            t = [SBOX[t[1]] ^ rcon, SBOX[t[2]], SBOX[t[3]], SBOX[t[0]]]
            rcon = XT[rcon]
        w += [w[i - 16 + j] ^ t[j] for j in range(4)]
    return [bytes(w[i:i + 16]) for i in range(0, 176, 16)]


SHIFT = [0, 5, 10, 15, 4, 9, 14, 3, 8, 13, 2, 7, 12, 1, 6, 11]


def encrypt_block(rk, block):
    s = [b ^ k for b, k in zip(block, rk[0])]
    for r in range(1, 11):
        s = [SBOX[s[i]] for i in SHIFT]                            # SubBytes + ShiftRows
        if r < 10:                                                 # MixColumns
            m = []
            for c in range(0, 16, 4):
                a0, a1, a2, a3 = s[c:c + 4]
                x = a0 ^ a1 ^ a2 ^ a3
                m += [a0 ^ x ^ XT[a0 ^ a1], a1 ^ x ^ XT[a1 ^ a2], a2 ^ x ^ XT[a2 ^ a3], a3 ^ x ^ XT[a3 ^ a0]]
            s = m
        s = [b ^ k for b, k in zip(s, rk[r])]
    return bytes(s)


def ctr(key, counter_block, data):
    """AES-CTR. counter_block: 16 bytes, incremented as a big-endian integer."""
    rk = expand_key(key)
    ctr_int = int.from_bytes(counter_block, "big")
    out = bytearray()
    for i in range(0, len(data), 16):
        ks = encrypt_block(rk, (ctr_int & ((1 << 128) - 1)).to_bytes(16, "big"))
        out += bytes(a ^ b for a, b in zip(data[i:i + 16], ks))
        ctr_int += 1
    return bytes(out)


def _dbl(b):
    v = int.from_bytes(b, "big") << 1
    if v >> 128:
        v ^= 0x87
    return (v & ((1 << 128) - 1)).to_bytes(16, "big")


def cmac_subkeys(key):
    k1 = _dbl(encrypt_block(expand_key(key), bytes(16)))
    return k1, _dbl(k1)


def cmac(key, msg):
    rk = expand_key(key)
    k1, k2 = cmac_subkeys(key)
    n = max(1, (len(msg) + 15) // 16)
    last = msg[16 * (n - 1):]
    if len(last) == 16:
        last = bytes(a ^ b for a, b in zip(last, k1))
    else:
        last = bytes(a ^ b for a, b in zip(last + b"\x80" + bytes(15 - len(last)), k2))
    x = bytes(16)
    for i in range(n - 1):
        x = encrypt_block(rk, bytes(a ^ b for a, b in zip(x, msg[16 * i:16 * i + 16])))
    return encrypt_block(rk, bytes(a ^ b for a, b in zip(x, last)))


def self_test():
    h = bytes.fromhex
    assert SBOX[0x53] == 0xED and SBOX[0] == 0x63
    rk = expand_key(h("000102030405060708090a0b0c0d0e0f"))
    assert encrypt_block(rk, h("00112233445566778899aabbccddeeff")) == h("69c4e0d86a7b0430d8cdb78070b4c55a")
    key = h("2b7e151628aed2a6abf7158809cf4f3c")
    pt = h("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51"
           "30c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710")
    assert ctr(key, h("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"), pt) == h(
        "874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff"
        "5ae4df3edbd5d35e5b4f09020db03eab1e031dda2fbe03d1792170a0f3009cee")
    assert cmac(key, b"") == h("bb1d6929e95937287fa37d129b756746")
    assert cmac(key, pt[:16]) == h("070a16b46b4d4144f79bdd9dd04a287c")
    assert cmac(key, pt[:40]) == h("dfa66747de9ae63030ca32611497c827")
    assert cmac(key, pt) == h("51f0bebf7e3b9d92fc49741779363cfe")
    print("aes_ref: all test vectors pass")


if __name__ == "__main__":
    self_test()
