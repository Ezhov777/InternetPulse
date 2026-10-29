from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import os
payload = os.urandom(65536)
class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *args): pass
    def do_HEAD(self):
        self.send_response(200); self.send_header('Content-Length','0'); self.end_headers()
    def do_GET(self):
        if self.path == '/error':
            self.send_response(503); self.send_header('Content-Length','0'); self.end_headers(); return
        self.send_response(200); self.send_header('Content-Length',str(16*1024*1024)); self.end_headers()
        try:
            for _ in range(256): self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError): pass
    def do_PUT(self):
        left = int(self.headers['Content-Length'])
        while left:
            chunk = self.rfile.read(min(left,65536))
            if not chunk: break
            left -= len(chunk)
        self.send_response(200); self.send_header('Content-Length','0'); self.end_headers()
class Server(ThreadingHTTPServer):
    # Python defaults to a backlog of five; the client intentionally opens nine connections.
    request_queue_size = 128
Server(('127.0.0.1',18762),Handler).serve_forever()
