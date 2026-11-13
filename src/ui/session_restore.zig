//! Session restore crash recovery subsystem.
//! Firefox about:sessionrestore parity: detects dirty/crashed shutdowns,
//! presents an interactive recovery dialog with container tab indicators,
//! allows granular tab selection, and restores tabs into TabManager.

const std = @import("std");
const TabManager = @import("tabs.zig").TabManager;
const ContainerId = @import("../common/types.zig").ContainerId;
const SavedSession = @import("../storage/sessions.zig").SavedSession;
const SavedTab = @import("../storage/sessions.zig").SavedTab;

pub const SessionRestoreDialog = struct {
    allocator: std.mem.Allocator,
    session: SavedSession,
    profile_dir: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, profile_dir: ?[]const u8) SessionRestoreDialog {
        return .{
            .allocator = allocator,
            .session = SavedSession.init(allocator),
            .profile_dir = profile_dir,
        };
    }

    pub fn deinit(self: *SessionRestoreDialog) void {
        self.session.deinit();
    }

    /// Loads session state from JSON string or file
    pub fn loadFromJson(self: *SessionRestoreDialog, json_data: []const u8) !void {
        self.session.deinit();
        self.session = try SavedSession.deserialize(self.allocator, json_data);
    }

    /// Checks if the previous shutdown was a crash
    pub fn isCrashRecoveryNeeded(self: *const SessionRestoreDialog) bool {
        return self.session.was_crashed and self.session.tabs.items.len > 0;
    }

    pub fn tabCount(self: *const SessionRestoreDialog) usize {
        return self.session.tabs.items.len;
    }

    pub fn selectAll(self: *SessionRestoreDialog) void {
        for (self.session.tabs.items) |*tab| {
            tab.is_selected = true;
        }
    }

    pub fn deselectAll(self: *SessionRestoreDialog) void {
        for (self.session.tabs.items) |*tab| {
            tab.is_selected = false;
        }
    }

    pub fn toggleTab(self: *SessionRestoreDialog, index: usize) void {
        if (index < self.session.tabs.items.len) {
            self.session.tabs.items[index].is_selected = !self.session.tabs.items[index].is_selected;
        }
    }

    pub fn selectedTabCount(self: *const SessionRestoreDialog) usize {
        var count: usize = 0;
        for (self.session.tabs.items) |tab| {
            if (tab.is_selected) count += 1;
        }
        return count;
    }

    /// Restores selected tabs into TabManager
    pub fn restoreSelected(self: *SessionRestoreDialog, tab_mgr: *TabManager) !usize {
        var restored: usize = 0;
        for (self.session.tabs.items) |tab| {
            if (tab.is_selected) {
                _ = try tab_mgr.newTab(tab.url, tab.title, tab.container);
                restored += 1;
            }
        }
        self.session.was_crashed = false;
        return restored;
    }

    /// Clears crashed session and discards previous tabs
    pub fn discard(self: *SessionRestoreDialog) void {
        self.session.deinit();
        self.session = SavedSession.init(self.allocator);
        self.session.was_crashed = false;
    }

    /// Renders modern Firefox about:sessionrestore crash recovery page
    pub fn renderHtml(self: *const SessionRestoreDialog, allocator: std.mem.Allocator) ![]u8 {
        var tab_rows: std.ArrayList(u8) = .empty;
        defer tab_rows.deinit(allocator);

        for (self.session.tabs.items, 0..) |tab, idx| {
            const checked = if (tab.is_selected) "checked" else "";
            const container_badge = switch (tab.container) {
                .Personal => "<span class=\"badge personal\">Personal</span>",
                .Work => "<span class=\"badge work\">Work</span>",
                .Banking => "<span class=\"badge banking\">Banking</span>",
                .Shopping => "<span class=\"badge shopping\">Shopping</span>",
                .Default => "",
            };

            const row = try std.fmt.allocPrint(
                allocator,
                \\        <tr class="tab-row">
                \\          <td style="width: 32px; text-align: center;">
                \\            <input type="checkbox" data-index="{d}" {s}>
                \\          </td>
                \\          <td>
                \\            <div class="tab-title">
                \\              {s}
                \\              <span style="font-weight: 600;">{s}</span>
                \\              {s}
                \\            </div>
                \\            <div class="tab-url">{s}</div>
                \\          </td>
                \\        </tr>
                \\
            ,
                .{
                    idx,
                    checked,
                    if (tab.is_pinned) "<span class=\"pinned-icon\">📌</span>" else "",
                    tab.title,
                    container_badge,
                    tab.url,
                },
            );
            defer allocator.free(row);
            try tab_rows.appendSlice(allocator, row);
        }

        return try std.fmt.allocPrint(
            allocator,
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\  <meta charset="utf-8">
            \\  <title>Restore Previous Session - Davoth</title>
            \\  <style>
            \\    body {{ margin: 0; padding: 0; background-color: #2b2a33; color: #fbfbfe; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }}
            \\    .container {{ max-width: 680px; margin: 48px auto; background-color: #1c1b22; border-radius: 8px; box-shadow: 0 8px 24px rgba(0,0,0,0.5); padding: 32px; }}
            \\    .header {{ display: flex; align-items: flex-start; gap: 16px; margin-bottom: 24px; }}
            \\    .warning-icon {{ font-size: 36px; line-height: 1; }}
            \\    h1 {{ font-size: 22px; margin: 0 0 8px 0; font-weight: 600; color: #ffffff; }}
            \\    p.subtitle {{ margin: 0; font-size: 14px; color: #cfcfd8; line-height: 1.5; }}
            \\    .tab-table {{ width: 100%; border-collapse: collapse; margin: 20px 0; background: #2b2a33; border-radius: 6px; overflow: hidden; }}
            \\    .tab-row {{ border-bottom: 1px solid #38383d; }}
            \\    .tab-row:last-child {{ border-bottom: none; }}
            \\    .tab-row td {{ padding: 10px 12px; }}
            \\    .tab-title {{ font-size: 14px; display: flex; align-items: center; gap: 8px; }}
            \\    .tab-url {{ font-size: 12px; color: #8f8f9d; margin-top: 2px; text-overflow: ellipsis; overflow: hidden; white-space: nowrap; max-width: 500px; }}
            \\    .badge {{ font-size: 11px; padding: 2px 6px; border-radius: 4px; font-weight: bold; color: white; }}
            \\    .badge.personal {{ background-color: #0060df; }}
            \\    .badge.work {{ background-color: #e22850; }}
            \\    .badge.banking {{ background-color: #12bc00; }}
            \\    .badge.shopping {{ background-color: #e55c00; }}
            \\    .pinned-icon {{ font-size: 12px; }}
            \\    .actions {{ display: flex; justify-content: flex-end; gap: 12px; margin-top: 24px; padding-top: 16px; border-top: 1px solid #38383d; }}
            \\    .btn {{ padding: 8px 18px; border-radius: 4px; font-size: 14px; font-weight: 500; cursor: pointer; border: none; }}
            \\    .btn-primary {{ background-color: #0060df; color: #ffffff; }}
            \\    .btn-primary:hover {{ background-color: #003eaa; }}
            \\    .btn-secondary {{ background-color: #42414d; color: #fbfbfe; }}
            \\    .btn-secondary:hover {{ background-color: #52525e; }}
            \\  </style>
            \\</head>
            \\<body>
            \\  <div class="container">
            \\    <div class="header">
            \\      <div class="warning-icon">⚠</div>
            \\      <div>
            \\        <h1>Well, this is embarrassing.</h1>
            \\        <p class="subtitle">Davoth closed unexpectedly while you were browsing. We've recovered {d} tabs from your previous session. Choose which ones to restore:</p>
            \\      </div>
            \\    </div>
            \\    <table class="tab-table">
            \\      <tbody>
            \\{s}
            \\      </tbody>
            \\    </table>
            \\    <div class="actions">
            \\      <button class="btn btn-secondary" onclick="discardSession()">Start New Session</button>
            \\      <button class="btn btn-primary" onclick="restoreSession()">Restore Session</button>
            \\    </div>
            \\  </div>
            \\</body>
            \\</html>
        ,
            .{
                self.session.tabs.items.len,
                tab_rows.items,
            },
        );
    }
};

test "session restore crash detection and tab recovery" {
    const allocator = std.testing.allocator;
    var dialog = SessionRestoreDialog.init(allocator, null);
    defer dialog.deinit();

    const json =
        \\{
        \\  "crashed": true,
        \\  "active_tab": 0,
        \\  "tabs": [
        \\    { "url": "https://davoth.org", "title": "Davoth Browser", "container": 0, "pinned": true },
        \\    { "url": "https://company.org", "title": "Work Intranet", "container": 2, "pinned": false },
        \\    { "url": "https://bank.com", "title": "Secure Online Banking", "container": 3, "pinned": false }
        \\  ]
        \\}
    ;

    try dialog.loadFromJson(json);
    try std.testing.expect(dialog.isCrashRecoveryNeeded());
    try std.testing.expectEqual(@as(usize, 3), dialog.tabCount());
    try std.testing.expectEqual(@as(usize, 3), dialog.selectedTabCount());

    // Deselect tab 2 (Banking)
    dialog.toggleTab(2);
    try std.testing.expectEqual(@as(usize, 2), dialog.selectedTabCount());

    // Restore selected tabs into TabManager
    var tab_mgr = TabManager.init(allocator);
    defer tab_mgr.deinit();

    const restored_count = try dialog.restoreSelected(&tab_mgr);
    try std.testing.expectEqual(@as(usize, 2), restored_count);
    try std.testing.expectEqual(@as(usize, 2), tab_mgr.tabs.items.len);
    try std.testing.expect(!dialog.session.was_crashed);

    // Verify restored tab 0 and 1
    const t0 = &tab_mgr.tabs.items[0];
    try std.testing.expectEqualStrings("https://davoth.org", t0.url);
    try std.testing.expectEqual(ContainerId.Default, t0.container);

    const t1 = &tab_mgr.tabs.items[1];
    try std.testing.expectEqualStrings("https://company.org", t1.url);
    try std.testing.expectEqual(ContainerId.Work, t1.container);

    // Test HTML rendering
    const html = try dialog.renderHtml(allocator);
    defer allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "Restore Previous Session") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Well, this is embarrassing") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Work Intranet") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "badge work") != null);
}
