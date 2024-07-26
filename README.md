# zxml: A Simple XML Parser for Zig

`zxml` is a lightweight and easy-to-use XML parsing library for the Zig programming language. It provides a straightforward API for parsing XML strings into a tree-like structure, allowing easy navigation and manipulation of XML data.

## Installation Steps:

### Adding the Library URL:

Use `zig fetch` command to save the library's URL and its hash to a `build.zig.zon` file.

```sh
zig fetch --save https://github.com/engusmaze/zxml/archive/9d1e91844d671276e22d4f51d390c456053ae5a4.tar.gz
```

### Adding the Dependency:

After saving the library's URL, you need to make it importable by your code in the `build.zig` file. This involves specifying the dependency and adding it to an executable or library.

```zig
pub fn build(b: *std.Build) void {
    // ...
    const zxml = b.dependency("zxml", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zxml", zxml.module("zxml"));
}
```

## Usage

Here's a quick example of how to use `zxml`:

```zig
const std = @import("std");
const zxml = @import("zxml");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // XML string to parse
    const xml_string =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<root>
        \\  <child id="1">Hello</child>
        \\  <child id="2">World</child>
        \\</root>
    ;

    // Parse the XML string
    const doc = try zxml.parse(allocator, xml_string);
    defer doc.deinit(allocator);

    // Access and print the root element
    const root = doc.search("root").next();
    std.debug.print("Root element: {s}\n", .{root});

    // Search for child elements
    var iter = root.search("child");
    while (iter.next()) |child| {
        if (child.getAttribute("id")) |id| {
            std.debug.print("Child {s}: {s}\n", .{ id, child });
        }
    }
}
```

## API Overview

### Parsing XML

```zig
pub fn parse(allocator: Allocator, data: []const u8) !Value
```

Parses an XML string into a `Value` structure.

### Value

The `Value` union represents different types of XML nodes:

- `document`: Root node containing all other nodes
- `element`: XML element with tag, attributes, and children
- `text`: Text content
- `declaration`: XML declaration

### Searching and Accessing Data

- `search(tag: []const u8)`: Search for child elements with a specific tag
- `getAttribute(name: []const u8)`: Retrieve an attribute value by name

### Memory Management

Don't forget to call `deinit()` on the root `Value` when you're done to free allocated memory:

```zig
doc.deinit(allocator);
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## TODO

- Add support for CDATA sections
- Implement XML writing functionality
- Add more comprehensive error reporting?
- Make tests
