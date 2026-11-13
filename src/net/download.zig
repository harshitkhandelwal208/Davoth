//! Download manager re-export for backwards compatibility.
const std = @import("std");
pub const downloads = @import("downloads.zig");
pub const DownloadState = downloads.DownloadState;
pub const DownloadItem = downloads.DownloadItem;
pub const DownloadManager = downloads.DownloadManager;
pub const MimeSniffer = downloads.MimeSniffer;
