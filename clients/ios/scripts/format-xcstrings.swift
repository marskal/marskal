// Writes String Catalogs the way Xcode does, so a catalog edited by a
// script or by hand diffs only where its content changed: two-space
// indents, `"key" : value`, an empty object as `{` blank line `}`, and keys
// in Unicode code point order.
//
//   xcrun swift scripts/format-xcstrings.swift <file.xcstrings>...

import Foundation

func string(_ value: String) throws -> String {
    let data = try JSONSerialization.data(
        withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self)
}

func write(_ value: Any, indent: String) throws -> String {
    let inner = indent + "  "
    switch value {
    case let object as [String: Any]:
        if object.isEmpty { return "{\n\n\(indent)}" }
        let keys = object.keys.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) }
        let members = try keys.map { "\(inner)\(try string($0)) : \(try write(object[$0]!, indent: inner))" }
        return "{\n" + members.joined(separator: ",\n") + "\n\(indent)}"
    case let array as [Any]:
        if array.isEmpty { return "[\n\n\(indent)]" }
        let items = try array.map { inner + (try write($0, indent: inner)) }
        return "[\n" + items.joined(separator: ",\n") + "\n\(indent)]"
    case let text as String:
        return try string(text)
    case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
        return number.boolValue ? "true" : "false"
    case let number as NSNumber:
        return number.stringValue
    default:
        return "null"
    }
}

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    let original = try Data(contentsOf: url)
    // Xcode ends the file without a newline.
    let formatted = Data(try write(JSONSerialization.jsonObject(with: original), indent: "").utf8)
    if formatted != original {
        try formatted.write(to: url, options: .atomic)
        print("Formatted \(path)")
    }
}
