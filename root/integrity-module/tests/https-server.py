import http.server
import json
import ssl
import sys
import threading

certfile, keyfile, outfile, fixture = sys.argv[1:5]


def serve(handler, tls):
    httpd = http.server.HTTPServer(("127.0.0.1", 0), handler)
    if tls:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(certfile, keyfile)
        httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd.server_address[1]


class Plain(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = open(fixture, "rb").read()
        self.send_response(200)
        self.send_header("Content-Type", "text/xml")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


plain_port = serve(Plain, False)


class Tls(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/redir"):
            self.send_response(302)
            self.send_header("Location", "http://127.0.0.1:%d/valid.xml" % plain_port)
            self.end_headers()
            return
        body = open(fixture, "rb").read()
        self.send_response(200)
        self.send_header("Content-Type", "text/xml")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


tls_port = serve(Tls, True)
with open(outfile, "w") as fh:
    json.dump({"tls": tls_port, "plain": plain_port}, fh)
threading.Event().wait()
