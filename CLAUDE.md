# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MiniKV is a lightweight in-memory Key-Value store written in Zig 0.15.x for learning purposes. It implements the Redis RESP v2 protocol and should be accessible via `redis-cli`.

## Build Commands

```bash
zig build              # Build the project
zig build run          # Build and run
zig build test         # Run all tests
zig build -Doptimize=Debug      # Debug build with leak detection
zig build -Doptimize=ReleaseFast # Optimized release build
```

## Architecture

Target architecture (from docs/project.md):

```
main.zig          → Entry point, config, signal handling
server.zig        → TCP listener, poll-based event loop, client management
protocol/
  resp.zig        → RESP v2 parser/serializer
  command.zig     → Command dispatcher
storage/
  engine.zig      → Storage engine (StringHashMap-based)
  string.zig      → String operations
  list.zig        → List operations (P3)
  hash.zig        → Hash operations (P3)
persistence/
  aof.zig         → AOF persistence (P3)
util/
  allocator.zig   → LoggingAllocator wrapper
  logger.zig      → Logging utilities
  config.zig      → Configuration management
```

## Allocator Strategy

- **GPA (GeneralPurposeAllocator)**: Application-wide parent allocator with leak detection
- **ArenaAllocator**: Per-client, reset after each request
- **FixedBufferAllocator**: Stack-based for RESP parsing

## Key Learning Points

- Zig 0.15 new `std.Io.Writer` / `std.Io.Reader` API with explicit buffer management
- `std.posix` for low-level socket operations
- Non-blocking I/O with poll/epoll
- New ArrayList API (unmanaged style with explicit allocator passing)

## Testing

Integration testing with redis-cli:
```bash
redis-cli -p 6379 PING
redis-cli -p 6379 SET foo bar
redis-cli -p 6379 GET foo
```

## Implementation Phases

- Phase 1 (MVP): PING, SET, GET
- Phase 2: DEL, EXISTS, KEYS, DBSIZE, FLUSHDB, INFO, ECHO, MSET, MGET, INCR, DECR
- Phase 3: Error handling, memory leak verification, graceful shutdown
- Phase 4-5: AOF persistence, List/Hash types (optional)
