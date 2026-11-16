"""The GPU path tracer's queue of glass-blocked NEE samples.

The diffuse kernel parks a sample whose straight shadow ray glass blocked (mnee_q_park); a resolve kernel runs the MNEE probe of
every entry at once (the probe's longest manifold solve sets the time of a launch, so it is paid once per flush, not once per
bounce round) and a reduce kernel adds each path's contributions in a fixed order, newest entry first, so a seeded render does not
depend on which thread took which slot. One device buffer: 16 header bytes (count, capacity, paths), a head word a path (its
newest entry + 1, 0 = none), then the entries; a zeroed buffer plus the header is an empty queue."""
from std.atomic import Atomic
from std.sys import size_of
from gonzales.core.geometry import Vec3f, RGB
from gonzales.core.spectrum import SampledWavelengths, SpectralSample


@fieldwise_init
struct MneeEntry(TrivialRegisterPassable):
    var throughput: SpectralSample   # the path's, as the diffuse kernel changes it after the probe's turn
    var contrib: SpectralSample      # the probe's clamped contribution (zero when it adds nothing); written by the resolve kernel
    var normal: Vec3f
    var hit_point: Vec3f
    var light_point: Vec3f
    var du: Vec3f
    var dv: Vec3f
    var alb: RGB
    var wavelengths: SampledWavelengths
    var pcg_state: UInt64            # the path's RNG as the inline probe would have read it
    var pcg_inc: UInt64
    var inv_pdf_area: Float32
    var light: Int32
    var bounce: Int32
    var medium: Int32
    var path: Int32
    var prev: Int32                  # the same path's previous entry + 1, 0 = none


def mnee_q_cap(n_paths: Int) -> Int:
    return min(n_paths, 1 << 21)


def _mnee_q_entries_at(n_paths: Int) -> Int:
    return 16 + (4 * n_paths + 15) // 16 * 16


def mnee_q_bytes(n_paths: Int, cap: Int) -> Int:
    return _mnee_q_entries_at(n_paths) + cap * size_of[MneeEntry]()


@always_inline
def mnee_q_header(q: Pointer[UInt8, MutUntrackedOrigin]) -> Pointer[Int32, MutUntrackedOrigin]:
    return q.unsafe_bitcast[Int32]()


@always_inline
def mnee_q_count(q: Pointer[UInt8, MutUntrackedOrigin]) -> Int:
    var h = mnee_q_header(q)
    return min(Int(h[unsafe_offset=0]), Int(h[unsafe_offset=1]))


@always_inline
def mnee_q_head(q: Pointer[UInt8, MutUntrackedOrigin], path: Int) -> Pointer[Int32, MutUntrackedOrigin]:
    return q.unsafe_offset(16).unsafe_bitcast[Int32]().unsafe_offset(path)


@always_inline
def mnee_q_entry(q: Pointer[UInt8, MutUntrackedOrigin], i: Int) -> Pointer[MneeEntry, MutUntrackedOrigin]:
    return q.unsafe_offset(_mnee_q_entries_at(Int(mnee_q_header(q)[unsafe_offset=2]))).unsafe_bitcast[MneeEntry]().unsafe_offset(i)


def mnee_q_park(q: Pointer[UInt8, MutUntrackedOrigin], path: Int, e: MneeEntry) -> Bool:
    """Takes the next slot; False when the queue is full (the caller then probes inline). Only the thread of `path` touches
    its head word within a bounce round, so the chain needs no atomics."""
    var h = mnee_q_header(q)
    var i = Int(Atomic[Int32].fetch_add(h, Int32(1)))
    if i >= Int(h[unsafe_offset=1]):
        return False
    var hp = mnee_q_head(q, path)
    var ep = mnee_q_entry(q, i)
    ep[] = e
    ep[].prev = hp[unsafe_offset=0]
    hp[unsafe_offset=0] = Int32(i + 1)
    return True
