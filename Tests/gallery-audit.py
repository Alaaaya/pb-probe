from pathlib import Path
s = Path("Sources/ProbeGalleryAudit.swift").read_text()
for forbidden in [".write(", "createDirectory", "copyItem", "removeItem", "mkdir(", "O_CREAT", "O_WRONLY", "register", "respring("]:
    assert forbidden not in s, forbidden
assert "O_RDONLY | O_NOFOLLOW | O_NONBLOCK" in s
assert "names.count <= 256" in s
assert "siblings.first" in s
assert "limit: 2_000_000" in s
assert "enumerator(" not in s
assert "AUDIT COMPLETE" in s and "try lease.close()" in s
assert "visibility UNKNOWN" in s
# Exercise actual marker parsing independently from the privileged lease.
start = s.index("    static func references")
end = s.index("    static func run", start)
fixture = """
import Foundation
enum ProbeGalleryAudit {
 static let markers = ["BE2EE206-9948-4F2B-BD3E-C02042EDBC5D", "00B33CEB-3768-4682-81AD-0384CDA80B22", "7400"]
""" + s[start:end] + """
}
let json = Data(#"{"posterUUID":"be2ee206-9948-4f2b-bd3e-c02042edbc5d","id":"7400"}"#.utf8)
precondition(ProbeGalleryAudit.references(json) == [true, false, true])
let binary = try PropertyListSerialization.data(fromPropertyList: ["id": "00B33CEB-3768-4682-81AD-0384CDA80B22"], format: .binary, options: 0)
precondition(ProbeGalleryAudit.references(binary) == [false, true, false])
precondition(ProbeGalleryAudit.references(Data("unrelated".utf8)) == [false, false, false])
print("READONLY GALLERY MARKER FIXTURES PASS")
"""
Path("/tmp/pb-gallery-fixtures.swift").write_text(fixture)
p = Path("Tests/bounded-access.py")
assert 'append(install' in Path("Sources/PBProbeApp.swift").read_text()
print("READONLY GALLERY SOURCE BOUNDS PASS")
