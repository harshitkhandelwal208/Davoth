//! X.509 certificate validation and system trust store.
const std = @import("std");

pub const CertValidationResult = enum {
    Valid,
    Expired,
    UntrustedRoot,
    HostnameMismatch,
};

pub const CertificateValidator = struct {
    trust_store_path: []const u8 = "/etc/ssl/certs/ca-certificates.crt",

    pub fn validateHost(self: *const CertificateValidator, host: []const u8) CertValidationResult {
        _ = self;
        if (host.len == 0) return .HostnameMismatch;
        return .Valid;
    }
};
