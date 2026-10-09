"""本地假门户：按真实锐捷 SAM + CAS 门户的跳转与接口行为模拟。

macOS（Swift）和 Windows（C#）两端的端到端测试都会启动它：

    python3 testing/fake_portal.py <端口>     # 打印 http://127.0.0.1:<端口> 后常驻

只用标准库。账号 2023000001 / 密码 right-pass 能登录成功，其他密码返回「密码错误」。
测试辅助接口：POST /__state 查看状态，POST /__reset 恢复到未认证。
"""

from __future__ import annotations

import json
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


KEY = "Qvy2L55c2aTCHUc6uX/Llw=="
EXECUTION = "e1s1-flowkey"
SESSION = "sess-123"
# 用 KEY 加密后的期望密文（AES-128-ECB/PKCS7，与门户前端 CryptoJS 一致）。
# 客户端加密结果必须与之逐字节相同，才能通过假门户的校验。
ENCRYPTED = {
    "right-pass": "KuypXznwmT+f2RVaRPlISg==",
    "{}": "Ii6DBPcKY/RNKmCO1LcKXQ==",
}


class FakePortal:
    def __init__(self, username="2023000001",
                 services=None, nas_ip="10.254.0.1"):
        self.username = username
        self.services = services if services is not None else [
            {"key": "电信", "value": "ctcc"}, {"key": "移动", "value": "cmcc"},
            {"key": "联通", "value": "unicom"}]
        self.nas_ip = nas_ip
        self.online = False
        self.cas_ok = False
        self.chosen = None
        self.calls: list[str] = []
        self.login_posts = 0
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), self._handler())
        self.base = "http://127.0.0.1:%d" % self.server.server_port
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()

    @property
    def probes(self):
        return ((self.base + "/generate_204", 204, None),)

    def _handler(self):
        portal = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def _send(self, code, body=b"", headers=None, ctype="text/html"):
                self.send_response(code)
                for k, v in (headers or {}).items():
                    self.send_header(k, v)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def _json(self, obj):
                self._send(200, json.dumps(obj, ensure_ascii=False).encode(), ctype="application/json")

            def _body(self):
                n = int(self.headers.get("Content-Length") or 0)
                return self.rfile.read(n).decode()

            def do_GET(self):
                u = urllib.parse.urlsplit(self.path)
                portal.calls.append("GET " + u.path)
                if u.path == "/generate_204":
                    if portal.online:
                        return self._send(204)
                    return self._send(302, headers={
                        "Location": portal.base + "/eportal/index.jsp?wlanuserip=10.1.2.3"})
                if u.path == "/eportal/index.jsp" or u.path == "/entry":
                    q = dict(urllib.parse.parse_qsl(u.query))
                    nas = portal.nas_ip if u.path == "/eportal/index.jsp" else q.get("nasip", "1.1.1.1")
                    loc = "/portal/portal-main?" + urllib.parse.urlencode({
                        "sessionId": SESSION, "userIp": "10.1.2.3", "nasIp": nas,
                        "customPageId": "page-1", "flowKey": "portal_auth", "userMac": "aabbccddeeff"})
                    return self._send(302, headers={"Location": loc})
                if u.path == "/portal/portal-main":
                    return self._send(200, b"<app-root></app-root>")
                if u.path == "/cas-sso/login":
                    return self._send(200, (
                        '<p id="login-croypto">%s</p><p id="login-page-flowkey">%s</p>'
                        % (KEY, EXECUTION)).encode())
                self._send(404)

            def do_POST(self):
                u = urllib.parse.urlsplit(self.path)
                portal.calls.append("POST " + u.path)
                body = self._body()
                if u.path == "/eportal/workFlow/getCurrentNode":
                    return self._json({"code": 200, "data": {"currentNodePath": "portal_auth"}})
                if u.path == "/cas-sso/login":
                    portal.login_posts += 1
                    f = dict(urllib.parse.parse_qsl(body))
                    good = (f.get("username") == portal.username
                            and f.get("password") == ENCRYPTED["right-pass"]
                            and f.get("execution") == EXECUTION
                            and f.get("captcha_payload") == ENCRYPTED["{}"])
                    if good:
                        portal.cas_ok = True
                        return self._send(302, headers={
                            "Location": portal.base + "/portal/callbackAuthorize?ticket=ST-1-abc"})
                    return self._send(401, '<p id="login-croypto">%s</p><span id="login-error-msg">'
                                           '用户不存在或者密码错误!</span>'.encode() % KEY.encode())
                if u.path == "/eportal/network/serviceSelection":
                    real_nas = json.loads(body).get("sessionId") == SESSION
                    return self._json({"code": 200, "data": portal.services if real_nas else []})
                if u.path == "/eportal/network/serviceLogin":
                    svc = json.loads(body).get("service")
                    if portal.cas_ok and svc in [s["value"] for s in portal.services]:
                        portal.online, portal.chosen = True, svc
                        return self._json({"code": 200, "data": {"authResult": "success"}})
                    return self._json({"code": 200, "data": {"authResult": "fail",
                                                             "authMessage": "认证失败"}})
                if u.path == "/__reset":  # 原生端测试用：恢复到未认证状态
                    portal.online, portal.cas_ok, portal.chosen, portal.login_posts = False, False, None, 0
                    return self._json({"ok": True})
                if u.path == "/__state":
                    return self._json({"online": portal.online, "chosen": portal.chosen,
                                       "login_posts": portal.login_posts})
                if u.path == "/eportal/network/offline":
                    portal.online = False
                    return self._json({"code": 200, "message": "success"})
                self._send(404)

        return H


if __name__ == "__main__":
    import sys
    import time

    port = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    fp = FakePortal()
    if port:
        fp.close()
        fp.server = ThreadingHTTPServer(("127.0.0.1", port), fp._handler())
        fp.base = "http://127.0.0.1:%d" % port
        threading.Thread(target=fp.server.serve_forever, daemon=True).start()
    print(fp.base, flush=True)
    while True:
        time.sleep(3600)
