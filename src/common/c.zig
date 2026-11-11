//! Safe, direct C ABI bindings for SQLite3, OpenSSL, FreeType, and GTK4.
const std = @import("std");

// --- SQLite3 Bindings ---
pub const sqlite3 = opaque {};
pub const sqlite3_stmt = opaque {};

pub const SQLITE_OK: c_int = 0;
pub const SQLITE_ROW: c_int = 100;
pub const SQLITE_DONE: c_int = 101;

pub extern "c" fn sqlite3_open(filename: [*:0]const u8, ppDb: *?*sqlite3) c_int;
pub extern "c" fn sqlite3_close(db: ?*sqlite3) c_int;
pub extern "c" fn sqlite3_exec(
    db: ?*sqlite3,
    sql: [*:0]const u8,
    callback: ?*const fn (?*anyopaque, c_int, [*c][*c]u8, [*c][*c]u8) callconv(.c) c_int,
    arg: ?*anyopaque,
    errmsg: *[*c]u8,
) c_int;
pub extern "c" fn sqlite3_prepare_v2(
    db: ?*sqlite3,
    zSql: [*:0]const u8,
    nByte: c_int,
    ppStmt: *?*sqlite3_stmt,
    pzTail: ?*?[*c]const u8,
) c_int;
pub extern "c" fn sqlite3_step(pStmt: ?*sqlite3_stmt) c_int;
pub extern "c" fn sqlite3_column_text(pStmt: ?*sqlite3_stmt, iCol: c_int) [*c]const u8;
pub extern "c" fn sqlite3_column_int(pStmt: ?*sqlite3_stmt, iCol: c_int) c_int;
pub extern "c" fn sqlite3_column_int64(pStmt: ?*sqlite3_stmt, iCol: c_int) i64;
pub extern "c" fn sqlite3_finalize(pStmt: ?*sqlite3_stmt) c_int;
pub extern "c" fn sqlite3_free(ptr: ?*anyopaque) void;

// --- OpenSSL Bindings ---
pub const SSL = opaque {};
pub const SSL_CTX = opaque {};
pub const SSL_METHOD = opaque {};
pub const EVP_CIPHER_CTX = opaque {};
pub const EVP_CIPHER = opaque {};
pub const EVP_MD = opaque {};

pub extern "c" fn OPENSSL_init_ssl(opts: u64, settings: ?*anyopaque) c_int;
pub extern "c" fn TLS_client_method() ?*const SSL_METHOD;
pub extern "c" fn SSL_CTX_new(meth: ?*const SSL_METHOD) ?*SSL_CTX;
pub extern "c" fn SSL_CTX_free(ctx: ?*SSL_CTX) void;
pub extern "c" fn SSL_CTX_set_default_verify_paths(ctx: ?*SSL_CTX) c_int;
pub extern "c" fn SSL_CTX_set_alpn_protos(ctx: ?*SSL_CTX, protos: [*c]const u8, protos_len: c_uint) c_int;
pub extern "c" fn SSL_new(ctx: ?*SSL_CTX) ?*SSL;
pub extern "c" fn SSL_free(ssl: ?*SSL) void;
pub extern "c" fn SSL_ctrl(ssl: ?*SSL, cmd: c_int, larg: c_long, parg: ?*anyopaque) c_long;
pub fn SSL_set_tlsext_host_name(s: ?*SSL, name: [*c]const u8) c_int {
    return @intCast(SSL_ctrl(s, 55, 0, @ptrCast(@constCast(name))));
}
pub extern "c" fn SSL_set_fd(s: ?*SSL, fd: c_int) c_int;
pub extern "c" fn SSL_connect(s: ?*SSL) c_int;
pub extern "c" fn SSL_get0_alpn_selected(ssl: ?*const SSL, data: *[*c]const u8, len: *c_uint) void;
pub extern "c" fn SSL_shutdown(s: ?*SSL) c_int;
pub extern "c" fn SSL_write(ssl: ?*SSL, buf: ?*const anyopaque, num: c_int) c_int;
pub extern "c" fn SSL_read(ssl: ?*SSL, buf: ?*anyopaque, num: c_int) c_int;

pub extern "c" fn PKCS5_PBKDF2_HMAC(
    pass: [*c]const u8,
    passlen: c_int,
    salt: [*c]const u8,
    saltlen: c_int,
    iter: c_int,
    digest: ?*const EVP_MD,
    keylen: c_int,
    out: [*c]u8,
) c_int;
pub extern "c" fn EVP_sha256() ?*const EVP_MD;
pub extern "c" fn EVP_aes_256_cbc() ?*const EVP_CIPHER;
pub extern "c" fn EVP_CIPHER_CTX_new() ?*EVP_CIPHER_CTX;
pub extern "c" fn EVP_CIPHER_CTX_free(c: ?*EVP_CIPHER_CTX) void;
pub extern "c" fn EVP_EncryptInit_ex(
    ctx: ?*EVP_CIPHER_CTX,
    cipher: ?*const EVP_CIPHER,
    impl: ?*anyopaque,
    key: [*c]const u8,
    iv: [*c]const u8,
) c_int;
pub extern "c" fn EVP_EncryptUpdate(
    ctx: ?*EVP_CIPHER_CTX,
    out: [*c]u8,
    outl: *c_int,
    in_buf: [*c]const u8,
    inl: c_int,
) c_int;
pub extern "c" fn EVP_EncryptFinal_ex(ctx: ?*EVP_CIPHER_CTX, out: [*c]u8, outl: *c_int) c_int;
pub extern "c" fn EVP_DecryptInit_ex(
    ctx: ?*EVP_CIPHER_CTX,
    cipher: ?*const EVP_CIPHER,
    impl: ?*anyopaque,
    key: [*c]const u8,
    iv: [*c]const u8,
) c_int;
pub extern "c" fn EVP_DecryptUpdate(
    ctx: ?*EVP_CIPHER_CTX,
    out: [*c]u8,
    outl: *c_int,
    in_buf: [*c]const u8,
    inl: c_int,
) c_int;
pub extern "c" fn EVP_DecryptFinal_ex(ctx: ?*EVP_CIPHER_CTX, out: [*c]u8, outl: *c_int) c_int;
pub extern "c" fn RAND_bytes(buf: [*c]u8, num: c_int) c_int;

// --- FreeType Bindings ---
pub const FT_Library = ?*anyopaque;
pub extern "c" fn FT_Init_FreeType(alibrary: *FT_Library) c_int;
pub extern "c" fn FT_Done_FreeType(library: FT_Library) c_int;

// --- GTK4 Bindings ---
pub const GtkApplication = opaque {};
pub const GtkWidget = opaque {};
pub const GtkWindow = opaque {};
pub const GtkBox = opaque {};
pub const GtkEntry = opaque {};
pub const GApplication = opaque {};

pub const GTK_ORIENTATION_VERTICAL: c_int = 1;
pub const GTK_ORIENTATION_HORIZONTAL: c_int = 0;
pub const G_APPLICATION_DEFAULT_FLAGS: c_int = 0;

pub extern "c" fn gtk_application_new(application_id: [*:0]const u8, flags: c_int) ?*GtkApplication;
pub extern "c" fn gtk_application_window_new(application: ?*GtkApplication) ?*GtkWidget;
pub extern "c" fn gtk_window_set_title(window: ?*GtkWindow, title: [*:0]const u8) void;
pub extern "c" fn gtk_window_set_default_size(window: ?*GtkWindow, width: c_int, height: c_int) void;
pub extern "c" fn gtk_box_new(orientation: c_int, spacing: c_int) ?*GtkWidget;
pub extern "c" fn gtk_entry_new() ?*GtkWidget;
pub extern "c" fn gtk_widget_set_hexpand(widget: ?*GtkWidget, expand: c_int) void;
pub extern "c" fn gtk_entry_set_placeholder_text(entry: ?*GtkEntry, text: [*:0]const u8) void;
pub extern "c" fn gtk_window_set_child(window: ?*GtkWindow, child: ?*GtkWidget) void;
pub extern "c" fn gtk_box_append(box: ?*GtkBox, child: ?*GtkWidget) void;
pub extern "c" fn gtk_window_present(window: ?*GtkWindow) void;
pub extern "c" fn g_application_run(application: ?*GApplication, argc: c_int, argv: [*c][*c]u8) c_int;
pub extern "c" fn g_object_unref(object: ?*anyopaque) void;
pub extern "c" fn g_signal_connect_data(
    instance: ?*anyopaque,
    detailed_signal: [*:0]const u8,
    c_handler: ?*const fn () callconv(.c) void,
    data: ?*anyopaque,
    destroy_data: ?*anyopaque,
    connect_flags: c_int,
) c_ulong;
