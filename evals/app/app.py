"""A tiny shop: lists products and orders over HTTP."""
from http.server import BaseHTTPRequestHandler, HTTPServer

from orders import ORDERS, PRODUCTS


def page(body: str) -> bytes:
    return f"""<!doctype html>
<html><head><link rel="stylesheet" href="/static/style.css"></head>
<body><nav><a href="/">Products</a> <a href="/orders">Orders</a></nav>{body}</body></html>""".encode()


class Shop(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            body = "<h1>Products</h1><ul>" + "".join(f"<li>{p.name} - {p.price} kr</li>" for p in PRODUCTS) + "</ul>"
        elif self.path == "/orders":
            body = "<h1>Orders</h1><ul>" + "".join(f"<li>#{o.id} {o.customer}: {o.total} kr</li>" for o in ORDERS) + "</ul>"
        elif self.path == "/static/style.css":
            self.send_response(200)
            self.send_header("Content-Type", "text/css")
            self.end_headers()
            self.wfile.write(open("static/style.css", "rb").read())
            return
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(page(body))


if __name__ == "__main__":
    HTTPServer(("", 8000), Shop).serve_forever()
