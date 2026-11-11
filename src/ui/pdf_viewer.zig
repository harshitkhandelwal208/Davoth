//! Built-in PDF viewer pipeline and rendering integration.
const std = @import("std");

pub const PdfDocument = struct {
    page_count: u32 = 1,
    title: []const u8 = "Document.pdf",

    pub fn renderPage(_: *PdfDocument, _: u32) void {}
};
