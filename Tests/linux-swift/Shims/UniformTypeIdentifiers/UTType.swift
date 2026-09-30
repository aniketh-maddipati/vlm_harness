// UTType stand-in (Linux sandbox only).
public struct UTType: Sendable {
    public let identifier: String
    public static let jpeg = UTType(identifier: "public.jpeg")
}
