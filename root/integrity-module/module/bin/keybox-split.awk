BEGIN {
    doc = ""
}

{ doc = doc $0 "\n" }

function strip_ws(s) {
    gsub(/[ \t\r\n]/, "", s)
    return s
}

function wrap(b64,   out, i, len) {
    out = ""
    len = length(b64)
    for (i = 1; i <= len; i += 64) {
        out = out substr(b64, i, 64) "\n"
    }
    return out
}

function emit_cert(block, file,   b64, body) {
    body = block
    if (!gsub(/-----BEGIN CERTIFICATE-----/, "", body)) return 0
    if (!gsub(/-----END CERTIFICATE-----/, "", body)) return 0
    gsub(/<[^>]*>/, "", body)
    b64 = strip_ws(body)
    if (length(b64) < 100) return 0
    if (b64 !~ /^[A-Za-z0-9+\/=]+$/) return 0
    printf "-----BEGIN CERTIFICATE-----\n%s-----END CERTIFICATE-----\n", wrap(b64) > file
    close(file)
    return 1
}

END {
    pos = 1
    k = 0
    certs_total = 0
    while ((p = index(substr(doc, pos), "<Key ")) > 0) {
        start = pos + p - 1
        e = index(substr(doc, start), "</Key>")
        if (e == 0) {
            print "error key-unclosed"
            exit 1
        }
        block = substr(doc, start, e + 5)
        k++
        alg = ""
        if (match(block, /algorithm="[A-Za-z0-9]+"/)) {
            alg = substr(block, RSTART + 11, RLENGTH - 12)
        }
        if (alg != "ecdsa" && alg != "rsa") {
            print "error unknown-algorithm"
            exit 1
        }
        priv = 0
        if (match(block, /<PrivateKey[^>]*>/)) {
            pk = substr(block, RSTART)
            pk = substr(pk, 1, index(pk, "</PrivateKey>") + 12)
            if (index(pk, "PRIVATE KEY-----") > 0) priv = 1
        }
        if (!priv) {
            print "error private-key"
            exit 1
        }
        nchain = 0
        if (index(block, "<CertificateChain>") > 0) nchain = 1
        if (!nchain) {
            print "error chain-missing"
            exit 1
        }
        chain_start = index(block, "<CertificateChain>")
        chain = substr(block, chain_start)
        chain = substr(chain, 1, index(chain, "</CertificateChain>") + 18)
        declared = ""
        if (match(chain, /<NumberOfCertificates>[0-9]+<\/NumberOfCertificates>/)) {
            declared = substr(chain, RSTART, RLENGTH)
            gsub(/[^0-9]/, "", declared)
        }
        cpos = 1
        n = 0
        while ((cp = index(substr(chain, cpos), "<Certificate ")) > 0) {
            cstart = cpos + cp - 1
            ce = index(substr(chain, cstart), "</Certificate>")
            if (ce == 0) {
                print "error cert-unclosed"
                exit 1
            }
            cblock = substr(chain, cstart, ce + 13)
            n++
            file = out "/cert-" k "-" n ".pem"
            if (!emit_cert(cblock, file)) {
                print "error cert-pem"
                exit 1
            }
            cpos = cstart + ce + 13
        }
        if (declared != "" && declared + 0 != n) {
            print "error cert-count"
            exit 1
        }
        if (n < 2) {
            print "error chain-short"
            exit 1
        }
        certs_total += n
        printf "key %d alg=%s certs=%d\n", k, alg, n
        pos = start + e + 5
    }
    if (k == 0) {
        print "error no-key"
        exit 1
    }
    printf "total keys=%d certs=%d\n", k, certs_total
}
