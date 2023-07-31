/// The main structure for a Rivit file
pub const Rivit = struct {
    lines: std.ArrayList(Line),
    allocator: mem.Allocator,
};

pub const Line = union(Kind) {
    pub const Kind = enum {
        header,
        nav_link,
        paragraph,
        block,
        list,
        embed,
    };

    pub const ListItem = struct {
        level: usize,
        value: std.ArrayList(StyledText),
        sublist: ?std.ArrayList(ListItem),
    };

    pub const Embed = struct {
        path: PlainText,
        alt_text: ?std.ArrayList(StyledText),
    };

    pub const Block = struct {
        indent: usize,
        body: PlainText,
    };

    header: PlainText,
    nav_link: PlainText,
    paragraph: std.ArrayList(StyledText),
    block: Block,
    list: std.ArrayList(ListItem),
    embed: Embed,
};

pub const PlainText = []const u8;

pub const StyledText = union(Kind) {
    pub const Kind = enum {
        unstyled,
        italic,
        bold,
        internal_link,
        external_link,
        escaped,
    };

    escaped: u8,
    unstyled: PlainText,
    italic: PlainText,
    bold: PlainText,
    internal_link: struct {
        name: PlainText,
        value: ?PlainText,
    },
    external_link: struct {
        url: PlainText,
        value: ?PlainText,
    },
};

pub fn parse(allocator: mem.Allocator, source: []const u8) !Rivit {
    var parsed = std.ArrayList(Line).init(allocator);

    var lines = mem.splitScalar(u8, source, '\n');
    while (lines.next()) |l| {
        var line = mem.trimRight(u8, l, whitespace);
        if (line.len == 0) continue;

        const delim = line[0];
        switch (delim) {
            // comments
            '#' => continue,

            // nav_link
            '+' => {
                line = line[1..]; // remove '+'

                const link = mem.trimLeft(u8, line, whitespace);
                if (link.len > 0) {
                    try parsed.append(.{
                        .nav_link = link,
                    });
                }
            },

            '.' => {
                const init_level = countPrefix(line, delim);

                line = mem.trimLeft(u8, line[init_level..], whitespace);
                if (line.len == 0) continue;

                var list = std.ArrayList(Line.ListItem).init(allocator);
                try list.append(.{
                    .level = init_level,
                    .value = std.ArrayList(StyledText).init(allocator),
                    .sublist = null,
                });

                var cur_list = &list.items[0];
                try parseStyledText(&cur_list.value, line);

                var prev_idx = lines.index;
                while (lines.next()) |nl| {
                    if (nl.len == 0 or nl[0] != delim) {
                        lines.index = prev_idx;
                        break;
                    }

                    const sublevel = countPrefix(nl, delim);
                    const text = mem.trim(u8, nl[sublevel..], whitespace);
                    if (text.len == 0) {
                        prev_idx = lines.index;
                        continue;
                    }

                    // if we have a sub-item, add it to cur_lists' sublist
                    if (sublevel > cur_list.level) {
                        if (cur_list.sublist == null) {
                            cur_list.sublist = std.ArrayList(Line.ListItem).init(allocator);
                        }

                        try cur_list.sublist.?.append(.{
                            .level = sublevel,
                            .value = std.ArrayList(StyledText).init(allocator),
                            .sublist = null,
                        });

                        cur_list = &cur_list.sublist.?.items[cur_list.sublist.?.items.len - 1];
                    }
                    // otherwise add it to the top-level list and set cur_list
                    else {
                        try list.append(.{
                            .level = sublevel,
                            .value = std.ArrayList(StyledText).init(allocator),
                            .sublist = null,
                        });

                        cur_list = &list.items[list.items.len - 1];
                    }

                    try parseStyledText(&cur_list.value, text);
                    prev_idx = lines.index;
                }

                try parsed.append(.{
                    .list = list,
                });
            },

            // embed
            '@' => {
                line = line[1..]; // remove '@'

                var path: []const u8 = "";
                var alt: []const u8 = "";

                line = mem.trimLeft(u8, line, whitespace);
                if (mem.indexOf(u8, line, " ")) |idx| {
                    path = line[0..idx];
                    alt = mem.trimLeft(u8, line[idx..], whitespace);
                } else {
                    path = line;
                }

                if (path.len > 0) {
                    var text: ?std.ArrayList(StyledText) = null;
                    if (alt.len > 0) {
                        var t = std.ArrayList(StyledText).init(allocator);
                        try parseStyledText(&t, alt);
                        text = t;
                    }

                    try parsed.append(.{
                        .embed = .{
                            .path = path,
                            .alt_text = text,
                        },
                    });
                }
            },

            // blocks
            ' ', '\t' => {
                const start = lines.index.? - (l.len + 1);
                const indent = countPrefix(line, delim);

                var prev_idx = lines.index;
                while (lines.next()) |nl| {
                    const nl_indent = countPrefix(nl, delim);
                    if (nl_indent < indent) {
                        lines.index = prev_idx;
                        break;
                    }

                    prev_idx = lines.index;
                }

                const end = prev_idx orelse lines.buffer.len;
                const block = lines.buffer[start .. end - 1];

                if (block.len > 0) {
                    try parsed.append(.{
                        .block = .{
                            .indent = indent,
                            .body = block,
                        },
                    });
                }
            },

            else => {
                var tmp = line;
                while (tmp.len > 0) {
                    if (ascii.isLower(tmp[0])) break;
                    tmp = tmp[1..];
                }

                // header
                if (tmp.len == 0) {
                    try parsed.append(.{
                        .header = line,
                    });
                }
                // paragraph
                else {
                    var text = std.ArrayList(StyledText).init(allocator);
                    try parseStyledText(&text, line);

                    try parsed.append(.{
                        .paragraph = text,
                    });
                }
            },
        }
    }

    return .{
        .lines = parsed,
        .allocator = allocator,
    };
}

fn parseStyledText(parsed: *std.ArrayList(StyledText), line: []const u8) !void {
    var i: usize = 0;
    while (i < line.len) {
        const c = line[i];
        switch (c) {
            // italic, bold
            '*' => {
                var start = i;
                var end = i;

                end += 1;
                var bold = end < line.len and line[end] == c;

                if (bold) {
                    end += 1;
                    while (end < line.len) : (end += 1) {
                        if (line[end] == c) {
                            if (end + 1 < line.len and line[end + 1] == c) {
                                end += 2;
                                break;
                            }
                        }
                    }

                    const text = mem.trim(u8, line[start + 2 .. end - 2], whitespace);
                    if (text.len > 0) {
                        try parsed.append(.{
                            .bold = text,
                        });
                    }
                } else {
                    while (end < line.len) : (end += 1) {
                        if (line[end] == c) {
                            end += 1;
                            break;
                        }
                    }

                    const text = mem.trim(u8, line[start + 1 .. end - 1], whitespace);
                    if (text.len > 0) {
                        try parsed.append(.{
                            .italic = text,
                        });
                    }
                }

                i = end;
            },

            // internal link
            '{', '[' => {
                var start = i;
                var end = i;

                const end_delim: u8 = if (c == '{') '}' else ']';

                while (end < line.len) : (end += 1) {
                    if (line[end] == end_delim) {
                        end += 1;
                        break;
                    }
                }

                var link = mem.trim(u8, line[start + 1 .. end - 1], whitespace);
                var value: ?PlainText = null;

                if (mem.indexOf(u8, link, " ")) |idx| {
                    value = mem.trimLeft(u8, link[idx..], whitespace);
                    link = mem.trimRight(u8, link[0..idx], whitespace);
                }

                if (link.len > 0) {
                    if (c == '{') {
                        try parsed.append(.{
                            .internal_link = .{
                                .name = link,
                                .value = value,
                            },
                        });
                    } else {
                        try parsed.append(.{
                            .external_link = .{
                                .url = link,
                                .value = value,
                            },
                        });
                    }
                }

                i = end;
            },

            // escaped characters
            '\\' => {
                i += 1;
                if (i < line.len) {
                    var chr = line[i];
                    if (ascii.isWhitespace(chr)) {
                        chr = '\\';
                    } else {
                        i += 1;
                    }

                    try parsed.append(.{ .escaped = chr });
                } else {
                    try parsed.append(.{ .escaped = '\\' });
                }
            },

            // plaintext
            else => {
                var start = i;
                var end = i;

                while (end < line.len) switch (line[end]) {
                    // escapes require their own state
                    '\\' => break,

                    '*', '{', '[' => {
                        // only swap states if the above are not touching whitespace
                        if (end + 1 < line.len and !ascii.isWhitespace(line[end + 1])) {
                            break;
                        }

                        end += 1;
                    },

                    else => end += 1,
                };

                const text = line[start..end];
                if (text.len > 0) {
                    try parsed.append(.{
                        .unstyled = text,
                    });
                }

                i = end;
            },
        }
    }
}

fn countPrefix(haystack: []const u8, needle: u8) usize {
    var count: usize = 0;
    for (haystack) |v| {
        if (v != needle) break;
        count += 1;
    }

    return count;
}

const whitespace = &ascii.whitespace;

const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;
