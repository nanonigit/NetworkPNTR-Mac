#!/usr/bin/python3
"""Forward authenticated host vsock streams to one fixed guest loopback service."""
import hmac
from pathlib import Path
import selectors
import socket
import threading
import time

PREFIX = b'ARTEX_VSOCK_1 '
CAPACITY = 16
BUFFER_LIMIT = 65536


def authenticate(connection, token):
    expected = PREFIX + token + b'\n'
    frame = bytearray()
    while len(frame) < len(expected):
        byte = connection.recv(1)
        if not byte:
            return False
        frame.extend(byte)
        if byte == b'\n':
            break
    return hmac.compare_digest(bytes(frame), expected)


def forward(client, backend):
    sockets = [client, backend]
    pending = [bytearray(), bytearray()]
    readable = [True, True]
    shut = [False, False]
    for connection in sockets:
        connection.setblocking(False)
    deadline = time.monotonic() + 300
    with selectors.DefaultSelector() as selector:
        while time.monotonic() < deadline:
            for index, connection in enumerate(sockets):
                events = 0
                if readable[index] and len(pending[1 - index]) < BUFFER_LIMIT:
                    events |= selectors.EVENT_READ
                if pending[index]:
                    events |= selectors.EVENT_WRITE
                if not readable[1 - index] and not pending[index] and not shut[index]:
                    connection.shutdown(socket.SHUT_WR)
                    shut[index] = True
                try:
                    selector.unregister(connection)
                except KeyError:
                    pass
                if events:
                    selector.register(connection, events, index)
            if not any(readable) and not any(pending):
                return
            for key, events in selector.select(1):
                index = key.data
                if events & selectors.EVENT_READ:
                    try:
                        data = sockets[index].recv(BUFFER_LIMIT - len(pending[1 - index]))
                    except BlockingIOError:
                        continue
                    if data:
                        pending[1 - index].extend(data)
                    else:
                        readable[index] = False
                    deadline = time.monotonic() + 300
                if events & selectors.EVENT_WRITE:
                    try:
                        sent = sockets[index].send(pending[index])
                    except BlockingIOError:
                        continue
                    del pending[index][:sent]
                    deadline = time.monotonic() + 300


def main():
    token = Path('/run/relay/transport.token').read_bytes().strip()
    if len(token) != 64 or any(byte not in b'0123456789abcdef' for byte in token):
        raise SystemExit('Invalid transport credential')
    listener = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    listener.bind((socket.VMADDR_CID_ANY, 8787))
    listener.listen(CAPACITY)
    slots = threading.BoundedSemaphore(CAPACITY)

    def serve(client):
        try:
            with client:
                client.settimeout(5)
                if not authenticate(client, token):
                    return
                with socket.create_connection(('127.0.0.1', 8787), timeout=5) as backend:
                    forward(client, backend)
        except (OSError, TimeoutError):
            pass  # A disconnected or invalid peer has no application-level response.
        finally:
            slots.release()

    while True:
        client, address = listener.accept()
        if address[0] != socket.VMADDR_CID_HOST or not slots.acquire(blocking=False):
            client.close()
            continue
        threading.Thread(target=serve, args=(client,), daemon=True).start()


if __name__ == '__main__':
    main()
