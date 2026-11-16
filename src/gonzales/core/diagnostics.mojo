"""One shape for every "the scene asked for something this renderer does not
have" message.

The dominant parser bug in this codebase is the silent drop: a branch that
recognises a value as "not mine" and quietly does nothing, so the scene
renders as a plausible image with no error and nobody looks (see
project_silent_asset_load_failures — nine-plus instances, each warning bolted
on after the bug was found). Every fallthrough calls warn_unsupported, so the
NEXT unhandled value says so by itself.

What each argument is for, in the message's own order:

    warn_unsupported("material type", "hair", "flat 50%-grey diffuse",
                     "diffuse, conductor, dielectric")
    Warning: unsupported material type 'hair' -- renders as flat 50%-grey
    diffuse. Supported: diffuse, conductor, dielectric

`effect` is what the reader will actually SEE, since that is what they are
looking at when they go searching: name the visible outcome ("renders as
empty space", "the shape is skipped"), never the internal one ("ignored").
"""


from std.ffi import external_call
from std.memory.alloc import unsafe_alloc


def warn(msg: String):
    """Print a warning and keep it (oiio.cc diag_add) for --check and --json."""
    print(msg)
    var m = msg
    external_call["diag_add", NoneType, Pointer[UInt8, MutUntrackedOrigin], Int32](
        m.unsafe_ptr().unsafe_mut_cast[True]().unsafe_origin_cast[MutUntrackedOrigin](), Int32(m.byte_length()))


def collected_warnings() -> List[String]:
    var out = List[String]()
    var buf = unsafe_alloc[UInt8](4096)
    for i in range(Int(external_call["diag_count", Int32]())):
        _ = external_call["diag_get", Int32, Int32, Pointer[UInt8, MutUntrackedOrigin], Int32](
            Int32(i), buf.unsafe_origin_cast[MutUntrackedOrigin](), Int32(4096))
        out.append(String(unsafe_from_utf8_ptr=buf.as_imm()))
    buf.unsafe_free()
    return out^


def warn_unsupported(kind: String, value: String, effect: String, supported: String):
    warn("Warning: unsupported " + kind + " '" + value + "' -- " + effect
         + ". Supported: " + supported)


def warn_unsupported_in(kind: String, value: String, owner_kind: String, owner: String,
                        effect: String, supported: String):
    """warn_unsupported plus the name of the thing that asked for it, for
    values that arrive attached to a named scene object (a medium, a texture)
    -- without the name, a big scene gives the reader no way to find it."""
    warn("Warning: unsupported " + kind + " '" + value + "' for " + owner_kind
         + " '" + owner + "' -- " + effect + ". Supported: " + supported)
