import os
import ssl
import json
import time
import socket
import urllib.request
import urllib.error

# =========================
# 환경변수 (Valkey)
# =========================
VALKEY_HOST       = os.environ.get("REDIS_HOST", "127.0.0.1")
VALKEY_PORT       = int(os.environ.get("REDIS_PORT", "6379"))
VALKEY_TLS        = os.environ.get("REDIS_TLS", "false").lower() == "true"
VALKEY_QUEUE_KEY  = os.environ.get("REDIS_QUEUE_KEY", "status_queue")
VALKEY_DLQ_KEY    = os.environ.get("REDIS_DLQ_KEY", "status_queue_dlq")  # 실패 누적 초과 시 보관 (선택)

EXPO_PUSH_URL     = os.environ.get("EXPO_PUSH_URL", "https://exp.host/--/api/v2/push/send")
EXPO_RECEIPT_URL  = os.environ.get("EXPO_RECEIPT_URL", "https://exp.host/--/api/v2/push/getReceipts")

HTTP_TIMEOUT_SEC  = float(os.environ.get("HTTP_TIMEOUT_SECONDS", "5"))
HTTP_MAX_RETRIES  = int(os.environ.get("HTTP_MAX_RETRIES", "3"))  # HTTP 재시도
MAX_PER_REQUEST   = 100  # Expo 권장
MAX_DEQUEUE_PER_INV = int(os.environ.get("MAX_DEQUEUE_PER_INVOCATION", "50"))  # 1회 호출 처리 최대 작업 수

# 작업 재시도(비즈니스) 최대 횟수: 실패 토큰만 선별 재전송
MAX_ATTEMPTS      = int(os.environ.get("MAX_ATTEMPTS", "3"))

# =========================
# Valkey(Resp) 유틸
# =========================
def _resp_send(sock, *args):
    buf = []
    buf.append(f"*{len(args)}\r\n")
    for arg in args:
        b = arg if isinstance(arg, bytes) else str(arg).encode("utf-8")
        buf.append(f"${len(b)}\r\n")
        buf.append(b.decode("utf-8"))
        buf.append("\r\n")
    sock.sendall("".join(buf).encode("utf-8"))

def _recv_line(sock):
    chunks = []
    while True:
        ch = sock.recv(1)
        if not ch:
            raise ConnectionError("Socket closed while reading line")
        if ch == b'\n':
            break
        chunks.append(ch)
    line = b"".join(chunks)
    if line.endswith(b'\r'):
        line = line[:-1]
    return line.decode("utf-8", errors="ignore")

def _recv_exact(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise ConnectionError("Socket closed while reading exact bytes")
        data += chunk
    return data

def _resp_parse(sock):
    first = sock.recv(1)
    if not first:
        raise ConnectionError("Socket closed reading RESP type")
    t = first.decode("utf-8", errors="ignore")

    if t == '+':  # Simple String
        return _recv_line(sock)
    if t == '-':  # Error
        return {"error": _recv_line(sock)}
    if t == ':':  # Integer
        return int(_recv_line(sock))
    if t == '$':  # Bulk String
        length = int(_recv_line(sock))
        if length == -1:
            return None
        data = _recv_exact(sock, length)
        _ = _recv_exact(sock, 2)  # \r\n
        return data.decode("utf-8", errors="ignore")
    if t == '*':  # Array
        count = int(_recv_line(sock))
        if count == -1:
            return None
        return [_resp_parse(sock) for _ in range(count)]
    raise ValueError(f"Unknown RESP type byte: {t}")

def valkey_cmd(sock, *args):
    _resp_send(sock, *args)
    return _resp_parse(sock)

def valkey_connect(host, port, use_tls=False, timeout=3):
    s = socket.create_connection((host, port), timeout=timeout)
    if use_tls:
        ctx = ssl.create_default_context()
        # 데모/내부망: 검증 비활성화 (운영에서는 검증 활성 권장)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        s = ctx.wrap_socket(s, server_hostname=host)
    return s

# =========================
# Expo Push 유틸
# =========================
def _chunks(lst, size):
    for i in range(0, len(lst), size):
        yield lst[i:i+size]

def _post_json(url: str, payload, timeout=HTTP_TIMEOUT_SEC):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url=url, data=data, method="POST",
        headers={"Content-Type": "application/json", "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = resp.read()
        return resp.getcode(), json.loads(body.decode("utf-8"))

def _retryable_post_json(url, payload):
    delay = 0.5
    for attempt in range(1, HTTP_MAX_RETRIES + 1):
        try:
            code, body = _post_json(url, payload)
            if 200 <= code < 300:
                return code, body
            if code == 429 or (500 <= code < 600):
                time.sleep(delay); delay *= 2
                continue
            return code, body
        except urllib.error.HTTPError as e:
            try:
                body = e.read().decode("utf-8")
            except Exception:
                body = str(e)
            if e.code == 429 or (500 <= e.code < 600):
                time.sleep(delay); delay *= 2
                continue
            return e.code, {"error": body}
        except urllib.error.URLError as e:
            time.sleep(delay); delay *= 2
            if attempt == HTTP_MAX_RETRIES:
                return 599, {"error": str(e)}
    return 599, {"error": "max retries exceeded"}

def build_expo_messages(tokens, title, body, route, params, opts):
    messages, filtered_tokens = [], []
    for t in tokens or []:
        if not (isinstance(t, str) and t.startswith("ExponentPushToken[")):
            # 잘못된 토큰 스킵
            continue
        msg = {
            "to": t,
            "title": title,
            "body": body,
            "sound": opts.get("sound", "default"),
            "badge": opts.get("badge"),
            "priority": opts.get("priority", "default"),
            "ttl": opts.get("ttl"),
            "channelId": opts.get("channelId"),
            "data": {"route": route, "params": params or {}},
        }
        messages.append({k: v for k, v in msg.items() if v is not None})
        filtered_tokens.append(t)
    return messages, filtered_tokens

def send_push_with_token_outcomes(tokens, title, body, route, params=None, **opts):
    """성공/실패 토큰을 구분해서 반환"""
    all_tickets, all_errors = [], []
    success_tokens, failed_tokens = [], []

    for batch in _chunks(tokens or [], MAX_PER_REQUEST):
        messages, aligned_tokens = build_expo_messages(batch, title, body, route, params, opts)
        if not messages:
            continue

        code, resp = _retryable_post_json(EXPO_PUSH_URL, messages)  # 배열 그대로 전송

        # 응답 파싱
        if 200 <= code < 300 and isinstance(resp, dict) and "data" in resp and isinstance(resp["data"], list):
            # data 길이는 요청 메시지 수와 동일
            for i, item in enumerate(resp["data"]):
                tok = aligned_tokens[i] if i < len(aligned_tokens) else None
                if isinstance(item, dict) and item.get("status") == "ok":
                    if "id" in item:
                        all_tickets.append(item["id"])
                    if tok:
                        success_tokens.append(tok)
                else:
                    # status != ok
                    if tok:
                        failed_tokens.append(tok)
                    all_errors.append(item if isinstance(item, dict) else {"error": item})
            if "errors" in resp:
                all_errors.extend(resp["errors"])
        else:
            # 전체 배치 실패 → 배치의 모든 토큰을 실패 처리
            failed_tokens.extend(aligned_tokens)
            all_errors.append({"http_code": code, "body": resp})

    return {
        "tickets": all_tickets,
        "errors": all_errors,
        "success_tokens": success_tokens,
        "failed_tokens": failed_tokens,
    }

def get_receipts(receipt_ids):
    if not receipt_ids:
        return {}
    code, resp = _retryable_post_json(EXPO_RECEIPT_URL, {"ids": receipt_ids})
    if 200 <= code < 300 and isinstance(resp, dict):
        return resp.get("data", {})
    return {"error": resp, "http_code": code}

# =========================
# 통합 Lambda 핸들러 (Enqueue + Dequeue + Send + Retry up to 3)
# =========================
def lambda_handler(event, context):
    task_data = event['detail']

    # ---- 1) 이벤트 → 작업 구성 후 Valkey에 LPUSH ----
    job = {
        "tokens": task_data.get("tokens", []),
        "title":  task_data.get("title", "알림 제목"),
        "body":   task_data.get("body", "알림 내용"),
        "route":  task_data.get("route", "/"),
        "params": task_data.get("params", {}),
        "opts": {
            "priority": task_data.get("priority"),
            "ttl":      task_data.get("ttl"),
            "channelId":task_data.get("channelId"),
            "sound":    task_data.get("sound", "default"),
            "badge":    task_data.get("badge"),
        },
        "attempt": 0,  # 최초 시도
    }

    enqueued = False
    ping_reply = None
    try:
        s = valkey_connect(VALKEY_HOST, VALKEY_PORT, use_tls=VALKEY_TLS, timeout=3)
        ping_reply = valkey_cmd(s, "PING")
        _ = valkey_cmd(s, "LPUSH", VALKEY_QUEUE_KEY, json.dumps(job, ensure_ascii=False))
        enqueued = True
        s.close()
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": f"Valkey enqueue failed: {str(e)}"}, ensure_ascii=False),
        }

    # ---- 2) 큐에서 작업을 RPOP 하여 처리 (최대 N개) ----
    processed, aggregate_errors, aggregate_tickets = [], [], []
    try:
        s = valkey_connect(VALKEY_HOST, VALKEY_PORT, use_tls=VALKEY_TLS, timeout=3)
        for _ in range(MAX_DEQUEUE_PER_INV):
            raw = valkey_cmd(s, "RPOP", VALKEY_QUEUE_KEY)
            if raw is None:
                break

            try:
                task = json.loads(raw)
            except Exception:
                # 손상 데이터는 폐기 → DLQ로 이동 가능
                if VALKEY_DLQ_KEY:
                    _ = valkey_cmd(s, "LPUSH", VALKEY_DLQ_KEY, raw)
                continue

            tokens = task.get("tokens", [])
            title  = task.get("title", "알림 제목")
            body   = task.get("body", "알림 내용")
            route  = task.get("route", "/")
            params = task.get("params", {})
            opts   = task.get("opts", {}) or {}
            attempt= int(task.get("attempt", 0))

            outcome = send_push_with_token_outcomes(tokens, title, body, route, params, **opts)

            # (옵션) 즉시 1회 영수증 조회 (운영에선 지연/별도 워커 권장)
            receipts = get_receipts(outcome["tickets"]) if outcome["tickets"] else {}

            processed.append({
                "attempt": attempt,
                "requested_tokens": len(tokens),
                "success_tokens": outcome["success_tokens"],
                "failed_tokens": outcome["failed_tokens"],
                "ticket_count": len(outcome["tickets"]),
                "tickets": outcome["tickets"],
                "errors": outcome["errors"],
                "receipts": receipts,
                "title": title,
                "route": route,
            })
            aggregate_tickets.extend(outcome["tickets"])
            aggregate_errors.extend(outcome["errors"])

            # 실패 토큰 재전송 (최대 MAX_ATTEMPTS)
            if outcome["failed_tokens"]:
                next_attempt = attempt + 1
                retry_task = {
                    "tokens": outcome["failed_tokens"],
                    "title": title,
                    "body": body,
                    "route": route,
                    "params": params,
                    "opts": opts,
                    "attempt": next_attempt,
                }
                if next_attempt < MAX_ATTEMPTS:
                    # 재시도 큐에 다시 적재
                    _ = valkey_cmd(s, "LPUSH", VALKEY_QUEUE_KEY, json.dumps(retry_task, ensure_ascii=False))
                else:
                    # 최대 시도 초과 → DLQ로
                    if VALKEY_DLQ_KEY:
                        _ = valkey_cmd(s, "LPUSH", VALKEY_DLQ_KEY, json.dumps(retry_task, ensure_ascii=False))

        s.close()
    except Exception as e:
        aggregate_errors.append({"stage": "dequeue_or_send", "error": str(e)})

    # ---- 3) 결과 반환 ----
    result = {
        "valkey_ping": ping_reply,
        "enqueued": enqueued,
        "processed_count": len(processed),
        "processed": processed,
        "total_tickets": len(aggregate_tickets),
        "total_errors": len(aggregate_errors),
        "errors": aggregate_errors,
        "max_attempts": MAX_ATTEMPTS,
    }
    print("Integrated push result:", json.dumps(result, ensure_ascii=False))
    return {"statusCode": 200, "body": json.dumps(result, ensure_ascii=False)}
