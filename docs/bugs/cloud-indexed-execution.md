# Indexed tool dispatch and transcript replay

## Reproduction and chronology

The pinned ChatAgent was exercised through its real HTTP provider and file-backed transcript store in two Linux processes. Each mode had one fixed Read of a temporary file on the first turn. The fixture required the actual tool result with the original arguments, call ID and signature. The first process exited and the witness file was removed before the second process resumed. The resumed turn required the same signed history and zero new tool uses.

The initial fixture treated the host-generated date reminder as a user turn. Its request oracle now recognizes the exact dated reminder shape. The corrected runtime RED at 0920bce passed Complete and failed Stream. The real tool result reported a missing file_path despite correct arguments in the replayed assistant history. RED 1db2758 extends the witness to interleaved indexed arguments, missing completion, transport error, length stop and cancellation. GREEN 1c2d095 uses the accumulated history blocks for completed indexed calls.

Review found additional execution boundaries. RED c4209b5 shows malformed arguments and missing or repeated IDs reaching execution. Its synchronous queue witness proves enqueue on cancellation from a tool-use callback. GREEN c48ac4e validates the whole batch before emitting events and waits for consumer acceptance before enqueue. RED 3e8aae8 covers early and unmatched argument fragments, canceled queue scheduling and a canceled semaphore waiter after the next turn changes the loop context. GREEN 4b4c242 binds early fragments to their starts, rejects unmatched inputs and holds the original turn context through dispatch and tool invocation. A package-graph setup error was resolved by running harness tests through the pinned application's module graph. An import and upstream test context argument were corrected before GREEN.

## Five Whys

1. Read received incomplete arguments because the execution buffer finalized on a signature event.
2. The signature event triggered finalization because the buffer assumed every non-argument event ended the current tool block.
3. The outgoing history had correct arguments because it used a separate indexed accumulator.
4. The runtime issue survived the earlier tests because they exercised the provider and accumulator directly, outside the ChatAgent tool executor.
5. A second process was needed to verify the product path because JSON encoding alone did not establish transcript reload and replay.

## Contributing paths and prevention

Protocol and assembly. Indexed fragments belong to their own call and can arrive before the matching start. Completed blocks supply both execution and transcript history. Batch validation checks raw JSON, identity and the absence of unmatched fragments before any indexed tool event.

Execution lifetime. The scheduler retains the original tool context. It checks cancellation before dispatch, after waiting for a semaphore slot and before the tool call. Consumer cancellation before batch enqueue produces zero queued tools. Late completions respect a result already emitted by interruption handling. Ordinary unindexed tools retain their early dispatch path.

Verification. Retain both actual process-restart cases, exact fixture authority checks, interleaving, premature EOF, length and transport failures, malformed batch, callback cancellation, canceled queue and semaphore wait cases. Keep the full isolated harness and application package regressions. The next runtime gate is the normal chat API across dedicated VM reboot with a persisted guest state disk.
