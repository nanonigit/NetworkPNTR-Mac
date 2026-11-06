# Cloud egress VM probe

Boot the pinned Linux candidate with a fresh private state disk and the same
virtio socket listener, request parser and response framer used by the broker.
Use authenticated application APIs to list models and send a streaming chat
for the OpenAI, Gemini and Groq presets. The debug-only upstream checks the
synthetic bearer, route and payload and supplies raw HTTP in small chunks.
It does not make network requests. Stop the VM with an OpenAI stream held open
and require cancellation. Require a stopped machine, zero guest network
interfaces other than loopback, zero shared mounts and clean credential audit.
