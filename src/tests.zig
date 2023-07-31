const std = @import("std");
const testing = std.testing;
const rivit = @import("rivit.zig");

test "parses basic styles text" {
    const src =
        \\# Basic styles
        \\*Italic*,   **bold**,{link},     [foo.bar external].
    ;

    const heap = std.heap.page_allocator;
    const riv = try rivit.parse(heap, src);

    try testing.expectEqual(riv.lines.items.len, 1);

    const line = riv.lines.items[0];
    try testing.expect(line == .paragraph);

    const italic = line.paragraph.items[0].italic;
    try testing.expectEqualSlices(u8, italic, "Italic");

    const bold = line.paragraph.items[2].bold;
    try testing.expectEqualSlices(u8, bold, "bold");

    const internal = line.paragraph.items[4].internal_link;
    try testing.expectEqualSlices(u8, internal.name, "link");
    try testing.expectEqual(internal.value, null);

    const external = line.paragraph.items[6].external_link;
    try testing.expectEqualSlices(u8, external.url, "foo.bar");
    try testing.expect(external.value != null);
    if (external.value) |v| {
        try testing.expectEqualSlices(u8, v, "external");
    }
}

test "parses weirdly formatted styles" {
    const src =
        \\# Weirdly formatted styles 
        \\**Another**   *paragraph*    {link foo bar baz}    [bar.baz this is a test]
    ;

    const heap = std.heap.page_allocator;
    const riv = try rivit.parse(heap, src);

    try testing.expectEqual(riv.lines.items.len, 1);

    const line = riv.lines.items[0];
    try testing.expect(line == .paragraph);

    const bold = line.paragraph.items[0].bold;
    try testing.expectEqualSlices(u8, bold, "Another");

    const italic = line.paragraph.items[2].italic;
    try testing.expectEqualSlices(u8, italic, "paragraph");

    const internal = line.paragraph.items[4].internal_link;
    try testing.expectEqualSlices(u8, internal.name, "link");
    try testing.expect(internal.value != null);
    if (internal.value) |v| {
        try testing.expectEqualSlices(u8, v, "foo bar baz");
    }

    const external = line.paragraph.items[6].external_link;
    try testing.expectEqualSlices(u8, external.url, "bar.baz");
    try testing.expect(external.value != null);
    if (external.value) |v| {
        try testing.expectEqualSlices(u8, v, "this is a test");
    }
}

test "special character pass-through" {
    const src =
        \\# Character passthrough
        \\10 * 30 * 2 { hello, world } [ goodbye world ]
    ;

    const heap = std.heap.page_allocator;
    const riv = try rivit.parse(heap, src);

    try testing.expectEqual(riv.lines.items.len, 1);

    const line = riv.lines.items[0];
    try testing.expect(line == .paragraph);
    try testing.expectEqual(line.paragraph.items.len, 1);

    const text = line.paragraph.items[0];
    try testing.expect(text == .unstyled);
    try testing.expectEqualSlices(u8, text.unstyled, "10 * 30 * 2 { hello, world } [ goodbye world ]");
}

test "character escaping" {
    const src =
        \\# Escaped characters
        \\10\*30\*2 \{hello world} \[goodbye world] \ escaped \\ 
    ;

    const heap = std.heap.page_allocator;
    const riv = try rivit.parse(heap, src);

    try testing.expectEqual(riv.lines.items.len, 1);

    const line = riv.lines.items[0];
    try testing.expect(line == .paragraph);
    try testing.expectEqual(line.paragraph.items.len, 12);

    const n1 = line.paragraph.items[0];
    try testing.expect(n1 == .unstyled);
    try testing.expectEqualSlices(u8, n1.unstyled, "10");

    const star1 = line.paragraph.items[1];
    try testing.expect(star1 == .escaped);
    try testing.expectEqual(star1.escaped, '*');

    const n2 = line.paragraph.items[2];
    try testing.expect(n2 == .unstyled);
    try testing.expectEqualSlices(u8, n2.unstyled, "30");

    const star2 = line.paragraph.items[3];
    try testing.expect(star2 == .escaped);
    try testing.expectEqual(star2.escaped, '*');

    const n3 = line.paragraph.items[4];
    try testing.expect(n3 == .unstyled);
    try testing.expectEqualSlices(u8, n3.unstyled, "2 ");

    const brace = line.paragraph.items[5];
    try testing.expect(brace == .escaped);
    try testing.expectEqual(brace.escaped, '{');

    const hello = line.paragraph.items[6];
    try testing.expect(hello == .unstyled);
    try testing.expectEqualSlices(u8, hello.unstyled, "hello world} ");

    const square = line.paragraph.items[7];
    try testing.expect(square == .escaped);
    try testing.expectEqual(square.escaped, '[');

    const goodbye = line.paragraph.items[8];
    try testing.expect(goodbye == .unstyled);
    try testing.expectEqualSlices(u8, goodbye.unstyled, "goodbye world] ");

    const s1 = line.paragraph.items[9];
    try testing.expect(s1 == .escaped);
    try testing.expectEqual(s1.escaped, '\\');

    const text = line.paragraph.items[10];
    try testing.expect(text == .unstyled);
    try testing.expectEqualSlices(u8, text.unstyled, " escaped ");

    const s2 = line.paragraph.items[11];
    try testing.expect(s2 == .escaped);
    try testing.expectEqual(s2.escaped, '\\');
}

test "parses spaced block" {
    const code =
        \\   int
        \\   main(int argc, char *argv[])
        \\   {
        \\      printf("hello, world\n");
        \\      return 0;
        \\   }
    ;

    const src =
        \\Below is indented with spaces
        \\
    ++ code ++
        \\
        \\Above is indented with spaces
    ;

    const heap = std.heap.page_allocator;
    const riv = try rivit.parse(heap, src);

    try testing.expectEqual(riv.lines.items.len, 3);

    const first = riv.lines.items[0];
    try testing.expect(first == .paragraph);
    try testing.expectEqual(first.paragraph.items.len, 1);
    try testing.expectEqualSlices(u8, "Below is indented with spaces", first.paragraph.items[0].unstyled);

    const second = riv.lines.items[1];
    try testing.expect(second == .block);
    try testing.expectEqual(second.block.indent, 3);
    try testing.expectEqualSlices(u8, code, second.block.body);

    const third = riv.lines.items[2];
    try testing.expect(third == .paragraph);
    try testing.expectEqual(third.paragraph.items.len, 1);
    try testing.expectEqualSlices(u8, "Above is indented with spaces", third.paragraph.items[0].unstyled);
}

test "parses tabbed block" {
    const code =
        \\	int
        \\	main(int argc, char *argv[])
        \\	{
        \\		printf("hello, world\n");
        \\		return 0;
        \\	}
    ;

    const src =
        \\Below is indented with tabs
        \\
    ++ code ++
        \\
        \\Above is indented with tabs
    ;

    const heap = std.heap.page_allocator;
    const riv = try rivit.parse(heap, src);

    try testing.expectEqual(riv.lines.items.len, 3);

    const first = riv.lines.items[0];
    try testing.expect(first == .paragraph);
    try testing.expectEqual(first.paragraph.items.len, 1);
    try testing.expectEqualSlices(u8, "Below is indented with tabs", first.paragraph.items[0].unstyled);

    const second = riv.lines.items[1];
    try testing.expect(second == .block);
    try testing.expectEqual(second.block.indent, 1);
    try testing.expectEqualSlices(u8, code, second.block.body);

    const third = riv.lines.items[2];
    try testing.expect(third == .paragraph);
    try testing.expectEqual(third.paragraph.items.len, 1);
    try testing.expectEqualSlices(u8, "Above is indented with tabs", third.paragraph.items[0].unstyled);
}

test "parses lists" {
    const src =
        \\. li1
        \\.. li1.1
        \\... li1.1.1
        \\. li2
        \\.. li2.1
        \\.. li2.2
        \\... li2.2.1
    ;

    const heap = std.heap.page_allocator;
    const riv = try rivit.parse(heap, src);

    try testing.expectEqual(riv.lines.items.len, 1);

    { // check first list
        const first = riv.lines.items[0];
        try testing.expect(first == .list);

        const list = first.list;
        try testing.expectEqual(list.items[0].level, 1);
        try testing.expectEqual(list.items[0].value.items.len, 1);
        try testing.expect(list.items[0].value.items[0] == .unstyled);
        try testing.expectEqualSlices(u8, list.items[0].value.items[0].unstyled, "li1");
        try testing.expect(list.items[0].sublist != null);
        try testing.expectEqual(list.items[0].sublist.?.items.len, 1);

        const sub = list.items[0].sublist.?.items[0];
        try testing.expectEqual(sub.level, 2);
        try testing.expectEqual(sub.value.items.len, 1);
        try testing.expect(sub.value.items[0] == .unstyled);
        try testing.expectEqualSlices(u8, sub.value.items[0].unstyled, "li1.1");
        try testing.expect(sub.sublist != null);
        try testing.expectEqual(sub.sublist.?.items.len, 1);

        const subsub = sub.sublist.?.items[0];
        try testing.expectEqual(subsub.level, 3);
        try testing.expectEqual(subsub.value.items.len, 1);
        try testing.expect(subsub.value.items[0] == .unstyled);
        try testing.expectEqualSlices(u8, subsub.value.items[0].unstyled, "li1.1.1");
        try testing.expect(subsub.sublist == null);
    }
}

test "parses embeds" {
    const src =
        \\@ foo.png
        \\@ bar.wav it works
        \\@ baz.svg **this works too**
    ;

    const heap = std.heap.page_allocator;
    const riv = try rivit.parse(heap, src);

    try testing.expectEqual(riv.lines.items.len, 3);

    const first = riv.lines.items[0];
    try testing.expect(first == .embed);
    try testing.expectEqualSlices(u8, first.embed.path, "foo.png");
    try testing.expect(first.embed.alt_text == null);

    const second = riv.lines.items[1];
    try testing.expect(second == .embed);
    try testing.expectEqualSlices(u8, second.embed.path, "bar.wav");
    try testing.expect(second.embed.alt_text != null);
    if (second.embed.alt_text) |alt| {
        try testing.expectEqual(alt.items.len, 1);
        try testing.expect(alt.items[0] == .unstyled);
        try testing.expectEqualSlices(u8, alt.items[0].unstyled, "it works");
    }

    const third = riv.lines.items[2];
    try testing.expect(third == .embed);
    try testing.expectEqualSlices(u8, third.embed.path, "baz.svg");
    try testing.expect(third.embed.alt_text != null);
    if (third.embed.alt_text) |alt| {
        try testing.expectEqual(alt.items.len, 1);
        try testing.expect(alt.items[0] == .bold);
        try testing.expectEqualSlices(u8, alt.items[0].bold, "this works too");
    }
}
