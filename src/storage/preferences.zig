//! Browser preferences, profiles, and privacy configuration.
const std = @import("std");

pub const TrackingProtectionLevel = enum {
    Standard,
    Strict,
    Custom,
};

pub const ThemeMode = enum {
    System,
    Light,
    Dark,
};

pub const Preferences = struct {
    homepage: []const u8 = "about:home",
    default_search_url: []const u8 = "https://duckduckgo.com/?q=",
    https_only_mode: bool = true,
    doh_enabled: bool = true,
    tracking_protection: TrackingProtectionLevel = .Strict,
    theme: ThemeMode = .Dark,
    vim_navigation: bool = false,
    hardware_acceleration: bool = true,
};
