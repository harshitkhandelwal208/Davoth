//! Custom themes and GTK4 appearance styling.
const std = @import("std");

pub const ThemeCss = struct {
    pub const dark =
        \\window { background-color: #1e1e2e; color: #cdd6f4; }
        \\headerbar { background-color: #181825; border-bottom: 1px solid #313244; }
        \\entry { background-color: #313244; color: #cdd6f4; border-radius: 8px; }
        \\tab { background-color: #181825; padding: 4px 12px; }
        \\tab:checked { background-color: #313244; font-weight: bold; }
    ;

    pub const light =
        \\window { background-color: #ffffff; color: #000000; }
        \\headerbar { background-color: #f0f0f0; border-bottom: 1px solid #d0d0d0; }
        \\entry { background-color: #ffffff; color: #000000; border-radius: 8px; }
    ;
};
