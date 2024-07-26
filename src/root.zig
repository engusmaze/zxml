const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const StringHashMap = std.StringHashMapUnmanaged;

pub const Attribute = ?[]const u8;

/// Represents an XML value, which can be a document, text, declaration, or element.
///
/// Example:
/// ~~~
/// const allocator = std.heap.page_allocator;
///
/// const xml_string = "<root><child>Hello</child></root>";
///
/// const doc = try zxml.parse(allocator, xml_string);
/// defer doc.deinit(allocator);
///
/// // Access the first element
/// const first = doc.document[0];
/// std.debug.print("First element: {s}\n", .{first});
/// ~~~
pub const Value = union(enum) {
    document: []Value,
    text: []const u8,
    declaration: struct {
        tag: []const u8,
        attributes: StringHashMap(Attribute),
    },
    element: struct {
        tag: []const u8,
        attributes: StringHashMap(Attribute),
        children: []Value,
    },

    /// Deallocates the memory used by the Value and its children.
    ///
    /// Example:
    /// ~~~
    /// const doc = try zxml.parse(allocator, xml_string);
    /// defer doc.deinit(allocator);
    /// ~~~
    pub fn deinit(self: *Value, allocator: Allocator) void {
        switch (self.*) {
            .element => |*elem| {
                elem.attributes.deinit(allocator);
                for (elem.children) |*child| {
                    child.deinit(allocator);
                }
                allocator.free(elem.children);
            },
            .declaration => |*decl| {
                decl.attributes.deinit(allocator);
            },
            else => {},
        }
    }

    fn formatAttributes(attributes: *const StringHashMap(Attribute), writer: anytype) !void {
        var iter = attributes.iterator();
        while (iter.next()) |entry| {
            try writer.print(" {s}", .{entry.key_ptr.*});
            if (entry.value_ptr.*) |value| {
                try writer.print("=\"{s}\"", .{value});
            }
        }
    }

    /// Formats the XML value as a string.
    ///
    /// Example:
    /// ~~~
    /// const doc = try parse(allocator, xml_string);
    /// defer doc.deinit(allocator);
    ///
    /// std.debug.print("Formatted XML: {s}\n", .{doc});
    /// ~~~
    pub fn format(
        self: *const Value,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self.*) {
            .text => |slice| try writer.print("{s}", .{slice}),
            .element => |elem| {
                try writer.print("<{s}", .{elem.tag});

                try formatAttributes(&elem.attributes, writer);

                if (elem.children.len > 0) {
                    try writer.writeAll(">");

                    for (elem.children) |child| {
                        try child.format(fmt, options, writer);
                    }

                    try writer.print("</{s}>", .{elem.tag});
                } else {
                    try writer.writeAll("/>");
                }
            },
            .document => |children| {
                for (children) |child| {
                    try child.format(fmt, options, writer);
                }
            },
            .declaration => |elem| {
                try writer.print("<?{s}", .{elem.tag});

                try formatAttributes(&elem.attributes, writer);

                try writer.writeAll("?>");
            },
        }
    }

    /// Retrieves an attribute value by name.
    ///
    /// Example:
    /// ~~~
    /// const element = doc.search("element").next().?;
    /// if (element.getAttribute("id")) |id| {
    ///     std.debug.print("Element ID: {s}\n", .{id});
    /// }
    /// ~~~
    pub fn getAttribute(self: *const Value, name: []const u8) ?Attribute {
        switch (self.*) {
            .element => |elem| return elem.attributes.get(name),
            .declaration => |decl| return decl.attributes.get(name),
            else => return null,
        }
    }

    /// SearchIterator is used to search for elements with a specific tag
    pub const SearchIterator = struct {
        ptr: [*]const Value,
        end: [*]const Value,
        tag: []const u8,

        pub fn init(values: []const Value, tag: []const u8) SearchIterator {
            return SearchIterator{
                .ptr = values.ptr,
                .end = values.ptr + values.len,
                .tag = tag,
            };
        }

        // Iterates through values to find the next matching tag
        pub fn next(self: *SearchIterator) ?*const Value {
            while (@intFromPtr(self.ptr) < @intFromPtr(self.end)) {
                const value: *const Value = @ptrCast(self.ptr);
                self.ptr += 1;
                switch (value.*) {
                    .element => |elem| {
                        if (std.mem.eql(u8, elem.tag, self.tag)) {
                            return value;
                        }
                    },
                    .declaration => |decl| {
                        if (std.mem.eql(u8, decl.tag, self.tag)) {
                            return value;
                        }
                    },
                    else => {},
                }
            }
            return null;
        }
    };

    /// Creates an iterator to search for child elements with a specific tag.
    ///
    /// Example:
    /// ~~~
    /// var iter = doc.search("child");
    /// while (iter.next()) |child| {
    ///     std.debug.print("Child: {s}\n", .{child});
    /// }
    /// ~~~
    pub fn search(self: *const Value, tag: []const u8) SearchIterator {
        return SearchIterator.init(switch (self.*) {
            .document => |elements| elements,
            .element => |elem| elem.children,
            else => &.{},
        }, tag);
    }
};

pub const Error = error{
    OutOfMemory,
    InvalidData,
};

fn whitespace(c: u8) bool {
    return switch (c) {
        ' ', '\t', '\n', '\r', '\x0B', '\x0C' => true,
        else => false,
    };
}
fn identifier(c: u8) bool {
    return switch (c) {
        '<', '>', '?', '/', '=', '"', ' ', '\t', '\n', '\r', '\x0B', '\x0C' => false,
        else => true,
    };
}
fn text(c: u8) bool {
    return switch (c) {
        '<', '>' => false,
        else => true,
    };
}

pub const Parser = struct {
    const Self = @This();

    pub const Point = struct {
        ptr: [*]const u8,

        inline fn add(self: Point, value: usize) Point {
            return Point{ .ptr = self.ptr + value };
        }
        inline fn lt(self: Point, other: Point) bool {
            return @intFromPtr(self.ptr) < @intFromPtr(other.ptr);
        }
        inline fn gt(self: Point, other: Point) bool {
            return @intFromPtr(self.ptr) > @intFromPtr(other.ptr);
        }
        inline fn sliceTo(self: Point, other: Point) []const u8 {
            return self.ptr[0 .. @intFromPtr(other.ptr) - @intFromPtr(self.ptr)];
        }
    };

    allocator: Allocator,
    point: Point,
    end: Point,

    pub fn init(allocator: Allocator, data: []const u8) Self {
        return Self{
            .allocator = allocator,
            .point = .{ .ptr = data.ptr },
            .end = .{ .ptr = data.ptr + data.len },
        };
    }

    fn seek(self: *Self) ?u8 {
        if (self.point.lt(self.end)) {
            return self.point.ptr[0];
        } else {
            return null;
        }
    }
    fn next(self: *Self) ?u8 {
        if (self.seek()) |value| {
            self.point.ptr += 1;
            return value;
        } else {
            return null;
        }
    }
    fn skip(self: *Self) void {
        self.point.ptr += 1;
    }
    fn back(self: *Self) void {
        self.point.ptr -= 1;
    }

    fn match(self: *Self, predicate: fn (char: u8) bool) bool {
        const result = predicate(self.seek() orelse return false);
        self.point.ptr += @intFromBool(result);
        return result;
    }
    fn matchChar(self: *Self, c: u8) bool {
        const result = (self.seek() orelse return false) == c;
        self.point.ptr += @intFromBool(result);
        return result;
    }

    fn skipMatching(self: *Self, predicate: fn (char: u8) bool) void {
        while (self.match(predicate)) {}
    }

    fn matchChars(self: *Self, chars: []const u8) bool {
        const next_point = self.point.add(chars.len);
        if (next_point.gt(self.end)) {
            return false;
        }
        for (chars, self.point.ptr) |a, b| {
            if (a != b) {
                return false;
            }
        }
        self.point = next_point;
        return true;
    }

    /// Parses children of an element until the closing tag is found
    inline fn parseElementChildren(self: *Parser, tag: []const u8, attributes: *StringHashMap(Attribute), children: *ArrayList(Value)) Error!Value {
        while (try self.parseValue()) |child| {
            try children.append(self.allocator, child);
        }
        if (self.matchChars("</")) {
            if (self.matchChars(tag)) {
                self.skipMatching(whitespace);
                if (self.matchChar('>')) {
                    children.items = try children.toOwnedSlice(self.allocator);
                    children.capacity = children.items.len;

                    return Value{ .element = .{
                        .tag = tag,
                        .attributes = attributes.*,
                        .children = children.items,
                    } };
                }
            }
        }
        return Error.InvalidData;
    }

    /// Parses attributes of an element or declaration
    inline fn parseElementAttributes(self: *Parser, is_declaration: bool, tag: []const u8, attributes: *StringHashMap(Attribute)) Error!Value {
        while (true) {
            self.skipMatching(whitespace);
            const name = property: {
                const start = self.point;
                self.skipMatching(identifier);
                break :property start.sliceTo(self.point);
            };
            if (name.len > 0) {
                if (self.matchChar('=')) {
                    // Parse attribute with value
                    if (!self.matchChar('"')) {
                        break;
                    }

                    const value = property: {
                        const start = self.point;
                        while (self.seek()) |c| {
                            switch (c) {
                                '"' => break,
                                '\\' => self.skip(), // Skip escaped characters
                                else => {},
                            }
                            self.skip();
                        }
                        break :property start.sliceTo(self.point);
                    };

                    if (!self.matchChar('"')) {
                        break;
                    }

                    const result = try attributes.getOrPut(self.allocator, name);
                    if (result.found_existing) {
                        break;
                    }
                    result.value_ptr.* = value;
                } else {
                    // Handle attributes without values
                    const result = try attributes.getOrPut(self.allocator, name);
                    if (result.found_existing) {
                        break;
                    }
                    result.value_ptr.* = null;
                }
            } else {
                // Check for end of element or declaration
                if (is_declaration) {
                    if (self.matchChars("?>")) {
                        return Value{ .declaration = .{
                            .tag = tag,
                            .attributes = attributes.*,
                        } };
                    }
                    break;
                }

                if (self.matchChars("/>")) {
                    // Self-closing element
                    return Value{ .element = .{
                        .tag = tag,
                        .attributes = attributes.*,
                        .children = &.{},
                    } };
                } else if (self.matchChar('>')) {
                    // Element with children
                    var children = ArrayList(Value){};
                    return self.parseElementChildren(tag, attributes, &children) catch |err| {
                        children.deinit(self.allocator);
                        return err;
                    };
                }
                break;
            }
        }
        return Error.InvalidData;
    }

    /// Parses an XML element or declaration
    inline fn parseElement(self: *Parser) Error!?Value {
        const is_declaration = self.matchChar('?');
        if (!is_declaration and self.matchChar('/')) {
            return null; // Closing tag, handled elsewhere
        }
        const tag = tag: {
            const start = self.point;
            self.skipMatching(identifier);
            break :tag start.sliceTo(self.point);
        };
        var attributes = StringHashMap(Attribute){};
        return self.parseElementAttributes(is_declaration, tag, &attributes) catch |err| {
            attributes.deinit(self.allocator);
            return err;
        };
    }

    /// Parses text content
    inline fn parseText(self: *Parser, value_start: Point) Error!?Value {
        const text_start = self.point;
        self.skipMatching(text);
        if (text_start.ptr == self.point.ptr) {
            return null;
        }
        const text_slice = value_start.sliceTo(self.point);
        if (text_slice.len == 0) {
            return null;
        }
        return Value{ .text = text_slice };
    }

    /// Skips over XML comments
    inline fn skipComment(self: *Self) !void {
        while (self.seek() != null) {
            if (self.matchChars("-->")) {
                return;
            }
            self.skip();
        }
        return Error.InvalidData;
    }

    /// Main parsing function for XML values (elements, text, or comments)
    pub fn parseValue(self: *Parser) Error!?Value {
        var value_start = self.point;

        self.skipMatching(whitespace);

        // Skip comments
        while (self.matchChars("<!--")) {
            try self.skipComment();
            value_start = self.point;
            self.skipMatching(whitespace);
        }

        const element_start = self.point;

        // Parse element if '<' is found, otherwise parse text
        return try (if (self.matchChar('<')) self.parseElement() else self.parseText(value_start)) orelse {
            self.point = element_start;
            return null;
        };
    }
};

/// Parses an XML string into a Value structure.
///
/// Example:
/// ~~~
/// const zxml = @import("zxml");
///
/// const allocator = std.heap.page_allocator;
///
/// const xml_string = "<root><child>Hello</child></root>";
///
/// const doc = try zxml.parse(allocator, xml_string);
/// defer doc.deinit(allocator);
///
/// std.debug.print("Number of root elements: {d}\n", .{doc.document.len});
/// ~~~
pub fn parse(allocator: Allocator, data: []const u8) !Value {
    var values = ArrayList(Value){};
    var parser = Parser.init(allocator, data);
    while (try parser.parseValue()) |value| {
        try values.append(allocator, value);
    }
    return Value{ .document = try values.toOwnedSlice(allocator) };
}
