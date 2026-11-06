# Dedicated VM cloud egress stream

Reserve guest-to-host vsock port 8790 on the running VM's virtio device. It has one request per connection. Only a running, ready VM can opt in. Admission is bounded across the process, and a stopped VM cancels all of its exchanges and removes its listener. The guest keeps its write side open until the exchange ends so EOF or another request byte can cancel upstream work. Neither macOS nor the guest opens an IP listener for this service.

The request prefix is 14 bytes. It contains ASCII ARXE, version 1, an operation byte, a flags byte with bit 0 for streaming, a zero reserved byte, a big-endian UInt16 key length and a big-endian UInt32 body length. Operation IDs 1 through 9 are OpenAI models, chat and responses, Anthropic models and messages, Gemini models and chat, and Groq models and chat. Validate the prefix before allocating, then read a printable ASCII key and bounded body. No host, URL, proxy, port or arbitrary header crosses this boundary.

Each response frame has a one-byte tag and a big-endian UInt32 length. Tag 1 contains a UInt16 HTTP status and one type byte (0 unspecified, 1 JSON, 2 event stream). Tag 2 contains up to 16 KiB of decoded body. Tag 3 has length zero and is the sole successful terminal. A rejected or interrupted exchange closes without tag 3. TLS and HTTP framing determine when that terminal can be sent.

Test the exact binary protocol and the worker on real local stream sockets with an injected upstream. A signed VM probe will exercise the installed listener separately before runtime activation. The broker's deadline covers request reads, resolved-destination use, TLS and response writes. The system resolver is synchronous, so a cancelled lookup can hold its bounded process slot until it returns.
