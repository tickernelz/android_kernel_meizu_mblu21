BEGIN {
    for (i = 0; i < 256; i++) {
        h = sprintf("%02x", i)
        val[h] = i
    }
    hex = ""
}

{ hex = hex $0 }

function b(pos) {
    if (pos < 0 || pos >= n) return -1
    h = substr(hex, pos * 2 + 1, 2)
    if (!(h in val)) return -1
    return val[h]
}

function tlv(pos,   t, x, cnt, k, v, len, hs) {
    t = b(pos)
    if (t < 0) return 0
    x = b(pos + 1)
    if (x < 0) return 0
    if (x < 128) {
        len = x
        hs = 2
    } else {
        cnt = x - 128
        if (cnt < 1 || cnt > 4) return 0
        len = 0
        for (k = 0; k < cnt; k++) {
            v = b(pos + 2 + k)
            if (v < 0) return 0
            len = len * 256 + v
        }
        hs = 2 + cnt
    }
    TT = t
    TL = len
    TC = pos + hs
    TE = TC + len
    return (TE <= n)
}

END {
    n = length(hex) / 2
    if (n < 100) {
        print "error short"
        exit 1
    }
    if (!tlv(0)) {
        print "error outer"
        exit 1
    }
    if (TT != 48 || TE != n) {
        print "error outer"
        exit 1
    }
    if (!tlv(TC) || TT != 48) {
        print "error tbs"
        exit 1
    }
    tbs_c = TC
    tbs_e = TE
    pos = tbs_c
    cnt = 0
    while (pos < tbs_e) {
        if (!tlv(pos)) {
            print "error child"
            exit 1
        }
        if (TE > tbs_e) {
            print "error child"
            exit 1
        }
        cnt++
        ctag[cnt] = TT
        cc[cnt] = TC
        cl[cnt] = TL
        pos = TE
    }
    idx = 0
    if (cnt > 0 && ctag[1] == 160) idx = 1
    if (cnt < idx + 5) {
        print "error fields"
        exit 1
    }
    print "issuer=" substr(hex, cc[idx + 3] * 2 + 1, cl[idx + 3] * 2)
    print "subject=" substr(hex, cc[idx + 5] * 2 + 1, cl[idx + 5] * 2)
}
