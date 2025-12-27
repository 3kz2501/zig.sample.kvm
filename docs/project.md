# MiniKV 要件定義書

## 1. プロジェクト概要

### 1.1 プロジェクト名

**MiniKV** - Zig製 軽量インメモリ Key-Value ストア

### 1.2 目的

Zig 0.15.x の主要機能を実践的に学習するための教育用プロジェクト。
Redis互換のRESPプロトコルを実装し、`redis-cli` からアクセス可能なKVSを構築する。

### 1.3 学習目標

| カテゴリ     | 学習項目                                             |
| ------------ | ---------------------------------------------------- |
| メモリ管理   | GPA, ArenaAllocator, FixedBufferAllocator の使い分け |
| メモリ管理   | カスタムアロケータの実装                             |
| メモリ管理   | 新しい ArrayList API（unmanaged）                    |
| I/O          | 新しい std.Io.Writer / std.Io.Reader API             |
| I/O          | バッファ管理と flush 戦略                            |
| ネットワーク | std.posix による低レベルソケット操作                 |
| ネットワーク | Non-blocking I/O とイベントループ                    |
| 設計         | プロトコルパーサーの実装                             |
| 設計         | レイヤードアーキテクチャ                             |
| 永続化       | ファイルI/O と AOF ログ                              |

---

## 2. 機能要件

### 2.1 コア機能

#### 2.1.1 String コマンド

| コマンド | 構文                             | 説明               | 優先度 |
| -------- | -------------------------------- | ------------------ | ------ |
| SET      | `SET key value`                  | キーに値を設定     | P0     |
| GET      | `GET key`                        | キーの値を取得     | P0     |
| DEL      | `DEL key [key ...]`              | キーを削除         | P0     |
| EXISTS   | `EXISTS key [key ...]`           | キーの存在確認     | P1     |
| MSET     | `MSET key value [key value ...]` | 複数キーを一括設定 | P2     |
| MGET     | `MGET key [key ...]`             | 複数キーを一括取得 | P2     |
| INCR     | `INCR key`                       | 値をインクリメント | P2     |
| DECR     | `DECR key`                       | 値をデクリメント   | P2     |

#### 2.1.2 キー管理コマンド

| コマンド | 構文                | 説明                         | 優先度 |
| -------- | ------------------- | ---------------------------- | ------ |
| KEYS     | `KEYS pattern`      | パターンにマッチするキー一覧 | P1     |
| DBSIZE   | `DBSIZE`            | キー総数を取得               | P1     |
| FLUSHDB  | `FLUSHDB`           | 全キーを削除                 | P1     |
| RENAME   | `RENAME key newkey` | キー名変更                   | P2     |
| TYPE     | `TYPE key`          | 値の型を取得                 | P2     |

#### 2.1.3 サーバー管理コマンド

| コマンド | 構文             | 説明             | 優先度 |
| -------- | ---------------- | ---------------- | ------ |
| PING     | `PING [message]` | 疎通確認         | P0     |
| ECHO     | `ECHO message`   | メッセージを返す | P1     |
| INFO     | `INFO [section]` | サーバー情報取得 | P1     |
| COMMAND  | `COMMAND`        | コマンド一覧     | P2     |
| SHUTDOWN | `SHUTDOWN`       | サーバー停止     | P2     |

#### 2.1.4 拡張機能（オプション）

| コマンド | 構文                          | 説明                     | 優先度 |
| -------- | ----------------------------- | ------------------------ | ------ |
| EXPIRE   | `EXPIRE key seconds`          | TTL設定                  | P3     |
| TTL      | `TTL key`                     | 残りTTL取得              | P3     |
| LPUSH    | `LPUSH key value [value ...]` | リスト先頭に追加         | P3     |
| RPUSH    | `RPUSH key value [value ...]` | リスト末尾に追加         | P3     |
| LPOP     | `LPOP key`                    | リスト先頭から取得・削除 | P3     |
| RPOP     | `RPOP key`                    | リスト末尾から取得・削除 | P3     |
| LRANGE   | `LRANGE key start stop`       | リスト範囲取得           | P3     |
| HSET     | `HSET key field value`        | ハッシュフィールド設定   | P3     |
| HGET     | `HGET key field`              | ハッシュフィールド取得   | P3     |
| HGETALL  | `HGETALL key`                 | ハッシュ全体取得         | P3     |

### 2.2 プロトコル要件

#### RESP (Redis Serialization Protocol) v2

```
データ型:
- Simple String: +OK\r\n
- Error:         -ERR message\r\n
- Integer:       :1000\r\n
- Bulk String:   $6\r\nfoobar\r\n （または $-1\r\n でNULL）
- Array:         *2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n
```

**要件:**

- RESP v2 のパース・シリアライズを完全実装
- redis-cli から接続・操作可能であること
- 不正なプロトコルに対して適切なエラーを返すこと

### 2.3 永続化要件（オプション）

#### AOF (Append-Only File)

- 書き込みコマンドをファイルに追記
- 設定可能な flush 間隔
  - `always`: 毎コマンド後に fsync
  - `everysec`: 1秒ごとに fsync（デフォルト）
  - `no`: OS任せ
- 起動時に AOF ファイルからリストア

---

## 3. 非機能要件

### 3.1 パフォーマンス

| 項目                 | 目標値          | 備考                  |
| -------------------- | --------------- | --------------------- |
| 同時接続数           | 100+            | poll/epoll で管理     |
| レイテンシ (GET/SET) | < 1ms           | ローカル環境          |
| スループット         | 10,000+ ops/sec | シングルスレッド      |
| メモリ効率           | -               | リークゼロ（GPA検証） |

### 3.2 信頼性

- **メモリリーク検出**: GPA の leak detection を有効化
- **グレースフルシャットダウン**: SIGINT/SIGTERM でクリーンアップ
- **エラーハンドリング**: パニックせず適切なエラーレスポンス

### 3.3 運用性

- **ログ出力**: 接続/切断/コマンド実行をログ
- **メトリクス**: INFO コマンドで統計情報取得
- **設定**: ポート番号、ログレベル等を起動時指定

---

## 4. アーキテクチャ

### 4.1 レイヤー構成

```
┌─────────────────────────────────────────────────────────────┐
│                      main.zig                               │
│  - エントリーポイント                                        │
│  - 設定パース                                               │
│  - シグナルハンドリング                                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     server.zig                              │
│  - TCP リスナー                                             │
│  - イベントループ (poll)                                     │
│  - 接続管理 (Client 構造体)                                  │
│  - リクエスト/レスポンスのルーティング                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    protocol/                                │
│  ├── resp.zig        - RESP パーサー/シリアライザ            │
│  └── command.zig     - コマンドディスパッチャー              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    storage/                                 │
│  ├── engine.zig      - ストレージエンジン本体                │
│  ├── string.zig      - String 型操作                        │
│  ├── list.zig        - List 型操作 (P3)                     │
│  └── hash.zig        - Hash 型操作 (P3)                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   persistence/                              │
│  └── aof.zig         - AOF 永続化 (P3)                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      util/                                  │
│  ├── allocator.zig   - LoggingAllocator                     │
│  ├── logger.zig      - ログ出力ユーティリティ                │
│  └── config.zig      - 設定管理                             │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 ディレクトリ構成

```
minikv/
├── build.zig
├── build.zig.zon
├── README.md
├── src/
│   ├── main.zig
│   ├── server.zig
│   ├── protocol/
│   │   ├── resp.zig
│   │   └── command.zig
│   ├── storage/
│   │   ├── engine.zig
│   │   ├── string.zig
│   │   ├── list.zig
│   │   └── hash.zig
│   ├── persistence/
│   │   └── aof.zig
│   └── util/
│       ├── allocator.zig
│       ├── logger.zig
│       └── config.zig
└── test/
    ├── resp_test.zig
    ├── storage_test.zig
    └── integration_test.zig
```

### 4.3 アロケータ戦略

```
┌─────────────────────────────────────────────────────────────┐
│                    Allocator Hierarchy                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  GPA (GeneralPurposeAllocator)                      │   │
│  │  - アプリケーション全体の親アロケータ                  │   │
│  │  - メモリリーク検出有効                              │   │
│  │  - thread_safe = true                               │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│          ┌───────────────┼───────────────┐                 │
│          ▼               ▼               ▼                 │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │   Storage    │ │    Server    │ │   Logging    │       │
│  │   Engine     │ │   (長期)     │ │  Allocator   │       │
│  │   (長期)     │ │              │ │  (ラッパー)   │       │
│  └──────────────┘ └──────────────┘ └──────────────┘       │
│                          │                                  │
│                          ▼                                  │
│                  ┌──────────────┐                          │
│                  │    Arena     │                          │
│                  │ (per Client) │                          │
│                  │ リクエスト単位 │                          │
│                  └──────────────┘                          │
│                          │                                  │
│                          ▼                                  │
│                  ┌──────────────┐                          │
│                  │ FixedBuffer  │                          │
│                  │ (RESP Parse) │                          │
│                  │ スタック上    │                          │
│                  └──────────────┘                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘

使い分けルール:
- 長期間保持するデータ → GPA 直接
- リクエスト処理中の一時データ → Arena (Client毎)
- パース時の固定サイズバッファ → FixedBufferAllocator
- デバッグ時 → LoggingAllocator でラップ
```

### 4.4 I/O バッファ戦略

```
┌─────────────────────────────────────────────────────────────┐
│                     I/O Buffer Strategy                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  【受信】                                                    │
│  Client.recv_buffer: [4096]u8                               │
│  - クライアント毎に固定サイズ                                 │
│  - 部分受信に対応（recv_len で追跡）                         │
│  - コマンド完了後にリセット                                  │
│                                                             │
│  【送信】                                                    │
│  Client.send_buffer: [4096]u8                               │
│  - std.Io.Writer のバッファとして使用                        │
│  - レスポンス構築後に flush                                  │
│                                                             │
│  【ログ】                                                    │
│  Server.log_buffer: [1024]u8                                │
│  - stdout 用の共有バッファ                                   │
│  - 各ログ出力後に即 flush                                    │
│                                                             │
│  【AOF】                                                     │
│  AofWriter.buffer: [8192]u8                                 │
│  - 大きめバッファで書き込み効率化                            │
│  - 設定に応じた flush 戦略                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. データモデル

### 5.1 Value 型

```
Value = union(enum) {
    string: []const u8,
    list: DoublyLinkedList([]const u8),    // P3
    hash: StringHashMap([]const u8),        // P3
}
```

### 5.2 ストレージ構造

```
Storage = struct {
    data: StringHashMap(Value),     // キー → 値
    expires: StringHashMap(i64),    // キー → 有効期限 (P3)
    allocator: Allocator,

    // 統計情報
    stats: struct {
        total_commands: u64,
        total_connections: u64,
        current_connections: u32,
        keyspace_hits: u64,
        keyspace_misses: u64,
        bytes_read: u64,
        bytes_written: u64,
    },
}
```

### 5.3 クライアント構造

```
Client = struct {
    socket: posix.socket_t,
    address: net.Address,           // 接続元アドレス

    recv_buffer: [4096]u8,
    recv_len: usize,
    send_buffer: [4096]u8,

    arena: ArenaAllocator,          // リクエスト毎にリセット

    created_at: i64,                // 接続時刻
    last_command_at: i64,           // 最終コマンド時刻
    commands_processed: u64,        // 処理コマンド数
}
```

---

## 6. API仕様

### 6.1 RESP パーサー

```
// 入力: バイト列
// 出力: RespValue または ParseError

RespValue = union(enum) {
    simple_string: []const u8,
    error_msg: []const u8,
    integer: i64,
    bulk_string: ?[]const u8,
    array: ?[]const RespValue,
}

ParseError = error {
    UnexpectedEnd,      // データ不足
    InvalidType,        // 不正な型バイト
    InvalidInteger,     // 整数パース失敗
    InvalidLength,      // 不正な長さ指定
    OutOfMemory,
}
```

### 6.2 コマンドハンドラー

```
// 各コマンドハンドラーの署名
fn handle(
    storage: *Storage,
    args: []const RespValue,
    arena: Allocator,
) CommandError!RespValue

CommandError = error {
    WrongNumberOfArguments,
    InvalidArgumentType,
    KeyNotFound,
    WrongType,              // WRONGTYPE Operation against a key holding the wrong kind of value
    OutOfMemory,
    SyntaxError,
}
```

### 6.3 ストレージエンジン

```
// String 操作
fn set(key: []const u8, value: []const u8) !void
fn get(key: []const u8) ?[]const u8
fn del(keys: []const []const u8) usize
fn exists(keys: []const []const u8) usize

// キー操作
fn keys(pattern: []const u8, arena: Allocator) ![]const []const u8
fn dbsize() usize
fn flushdb() void
fn rename(old: []const u8, new: []const u8) !void
fn keyType(key: []const u8) ?ValueType

// 統計
fn info() Stats
```

---

## 7. 実装フェーズ

### Phase 1: 最小実装（MVP）

**目標**: redis-cli で PING/SET/GET が動作する

| タスク             | 成果物               | 学習ポイント                     |
| ------------------ | -------------------- | -------------------------------- |
| プロジェクト初期化 | build.zig, main.zig  | Zig 0.15 ビルドシステム          |
| RESP パーサー      | protocol/resp.zig    | FixedBufferAllocator, パース処理 |
| TCP サーバー       | server.zig           | std.posix, Non-blocking I/O      |
| ストレージ基礎     | storage/engine.zig   | HashMap, GPA                     |
| PING/SET/GET       | protocol/command.zig | 新 ArrayList API                 |

**完了条件**:

```bash
$ redis-cli -p 6379 PING
PONG
$ redis-cli -p 6379 SET foo bar
OK
$ redis-cli -p 6379 GET foo
"bar"
```

### Phase 2: 基本機能拡充

**目標**: 基本的なKVS操作が一通り動作

| タスク      | 成果物           | 学習ポイント           |
| ----------- | ---------------- | ---------------------- |
| DEL/EXISTS  | command.zig 拡張 | 複数引数処理           |
| KEYS/DBSIZE | command.zig 拡張 | イテレータ, Arena      |
| INFO        | command.zig 拡張 | 統計収集, フォーマット |
| MSET/MGET   | command.zig 拡張 | バルク操作             |
| ログ出力    | util/logger.zig  | 新 std.Io.Writer       |

**完了条件**:

- 全 P0/P1 コマンドが動作
- 接続/切断/コマンドのログ出力

### Phase 3: 堅牢化

**目標**: 本番品質に近づける

| タスク                     | 成果物             | 学習ポイント       |
| -------------------------- | ------------------ | ------------------ |
| エラーハンドリング         | 各モジュール       | エラーユニオン設計 |
| メモリリーク検証           | -                  | GPA leak detection |
| LoggingAllocator           | util/allocator.zig | カスタムアロケータ |
| グレースフルシャットダウン | main.zig           | シグナル処理       |
| 設定ファイル               | util/config.zig    | コマンドライン引数 |

**完了条件**:

- `zig build -Doptimize=Debug` でリーク検出ゼロ
- Ctrl+C で正常終了

### Phase 4: 永続化（オプション）

**目標**: 再起動後もデータが残る

| タスク       | 成果物              | 学習ポイント                 |
| ------------ | ------------------- | ---------------------------- |
| AOF 書き込み | persistence/aof.zig | ファイル I/O, flush 戦略     |
| AOF リストア | persistence/aof.zig | 起動時リプレイ               |
| BGSAVE 相当  | -                   | (発展) fork/スナップショット |

### Phase 5: データ型拡張（オプション）

**目標**: List/Hash 型サポート

| タスク    | 成果物             | 学習ポイント       |
| --------- | ------------------ | ------------------ |
| List 実装 | storage/list.zig   | DoublyLinkedList   |
| Hash 実装 | storage/hash.zig   | ネストした HashMap |
| TTL 実装  | storage/engine.zig | タイマー, 遅延削除 |

---

## 8. テスト方針

### 8.1 ユニットテスト

```zig
// 各モジュール内にテストを配置
test "RESP parser - simple string" {
    var parser = RespParser.init("+OK\r\n");
    const result = try parser.parse(testing.allocator);
    try testing.expectEqual(result, .{ .simple_string = "OK" });
}

test "Storage - set and get" {
    var storage = Storage.init(testing.allocator);
    defer storage.deinit();

    try storage.set("key", "value");
    try testing.expectEqualStrings("value", storage.get("key").?);
}
```

### 8.2 統合テスト

```bash
# redis-cli を使った手動テスト
redis-cli -p 6379 < test/commands.txt

# または redis-benchmark
redis-benchmark -p 6379 -t set,get -n 10000
```

### 8.3 メモリテスト

```bash
# Debug ビルドで実行し、終了時にリーク検出
zig build -Doptimize=Debug
./zig-out/bin/minikv
# Ctrl+C で終了 → リークがあれば報告される
```

---

## 9. 開発環境

### 9.1 必要ツール

| ツール      | バージョン | 用途               |
| ----------- | ---------- | ------------------ |
| Zig         | 0.15.x     | コンパイラ         |
| redis-cli   | any        | テストクライアント |
| netcat (nc) | any        | 低レベルテスト     |

### 9.2 推奨エディタ設定

- ZLS (Zig Language Server) 導入
- フォーマッタ: `zig fmt`

### 9.3 ビルドコマンド

```bash
# 開発ビルド（デバッグ情報あり、最適化なし）
zig build

# リリースビルド
zig build -Doptimize=ReleaseFast

# テスト実行
zig build test

# 実行
zig build run

# クリーン
rm -rf zig-out .zig-cache
```

---

## 10. 参考資料

### Redis プロトコル

- [RESP Protocol Specification](https://redis.io/docs/reference/protocol-spec/)
- [Redis Commands](https://redis.io/commands/)

### Zig 0.15

- [Zig 0.15.1 Release Notes](https://ziglang.org/download/0.15.1/release-notes.html)
- [Zig Standard Library Documentation](https://ziglang.org/documentation/master/std/)

### ネットワークプログラミング

- [Beej's Guide to Network Programming](https://beej.us/guide/bgnet/)
- [TCP Server in Zig](https://www.openmymind.net/TCP-Server-In-Zig-Part-1-Single-Threaded/)

---

## 付録A: コマンド実装チェックリスト

```
[ ] PING      - P0 - Phase 1
[ ] SET       - P0 - Phase 1
[ ] GET       - P0 - Phase 1
[ ] DEL       - P0 - Phase 2
[ ] EXISTS    - P1 - Phase 2
[ ] KEYS      - P1 - Phase 2
[ ] DBSIZE    - P1 - Phase 2
[ ] FLUSHDB   - P1 - Phase 2
[ ] INFO      - P1 - Phase 2
[ ] ECHO      - P1 - Phase 2
[ ] MSET      - P2 - Phase 2
[ ] MGET      - P2 - Phase 2
[ ] INCR      - P2 - Phase 2
[ ] DECR      - P2 - Phase 2
[ ] RENAME    - P2 - Phase 3
[ ] TYPE      - P2 - Phase 3
[ ] COMMAND   - P2 - Phase 3
[ ] SHUTDOWN  - P2 - Phase 3
[ ] EXPIRE    - P3 - Phase 5
[ ] TTL       - P3 - Phase 5
[ ] LPUSH     - P3 - Phase 5
[ ] RPUSH     - P3 - Phase 5
[ ] LPOP      - P3 - Phase 5
[ ] RPOP      - P3 - Phase 5
[ ] LRANGE    - P3 - Phase 5
[ ] HSET      - P3 - Phase 5
[ ] HGET      - P3 - Phase 5
[ ] HGETALL   - P3 - Phase 5
```

---

## 付録B: RESP プロトコル早見表

```
┌─────────────────────────────────────────────────────────────┐
│                    RESP v2 Quick Reference                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Simple String (成功レスポンス)                              │
│  +OK\r\n                                                    │
│                                                             │
│  Error (エラーレスポンス)                                    │
│  -ERR unknown command 'foo'\r\n                             │
│  -WRONGTYPE Operation against a key holding wrong type\r\n │
│                                                             │
│  Integer (整数)                                             │
│  :1000\r\n                                                  │
│  :0\r\n                                                     │
│                                                             │
│  Bulk String (バイナリセーフ文字列)                          │
│  $6\r\nfoobar\r\n      (長さ6の文字列 "foobar")            │
│  $0\r\n\r\n            (空文字列)                           │
│  $-1\r\n               (NULL)                               │
│                                                             │
│  Array (配列)                                               │
│  *2\r\n                (要素数2の配列)                      │
│  $3\r\nfoo\r\n         (1番目: "foo")                       │
│  $3\r\nbar\r\n         (2番目: "bar")                       │
│                                                             │
│  *0\r\n                (空配列)                             │
│  *-1\r\n               (NULL配列)                           │
│                                                             │
│  コマンド例: SET foo bar                                     │
│  *3\r\n$3\r\nSET\r\n$3\r\nfoo\r\n$3\r\nbar\r\n             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 付録C: エラーメッセージ一覧

| エラー    | メッセージ                                                          | 発生条件           |
| --------- | ------------------------------------------------------------------- | ------------------ |
| ERR       | `ERR unknown command '{cmd}'`                                       | 未知のコマンド     |
| ERR       | `ERR wrong number of arguments for '{cmd}' command`                 | 引数数不正         |
| ERR       | `ERR syntax error`                                                  | 構文エラー         |
| ERR       | `ERR value is not an integer or out of range`                       | INCR/DECR で非整数 |
| WRONGTYPE | `WRONGTYPE Operation against a key holding the wrong kind of value` | 型不一致           |
