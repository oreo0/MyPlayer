"""Make a tiny uncompressed QuickTime fixture without a hardware encoder."""
import struct
import sys
from pathlib import Path

def u32(*values): return struct.pack('>' + 'I' * len(values), *values)
def u16(*values): return struct.pack('>' + 'H' * len(values), *values)
def atom(name, data): return u32(len(data) + 8) + name.encode('ascii') + data
matrix = u32(65536, 0, 0, 0, 65536, 0, 0, 0, 1073741824)
frames = 20
frame = b'\x20\x40\x60' * (64 * 64)
ftyp = atom('ftyp', b'qt  ' + u32(0) + b'qt  ')
mdat = atom('mdat', frame * frames)
mvhd = atom('mvhd', u32(0, 0, 0, 600, frames * 600, 65536) + u16(256) + bytes(10) + matrix + bytes(24) + u32(2))
tkhd = atom('tkhd', u32(7, 0, 0, 1, 0, frames * 600) + bytes(8) + u16(0, 0, 0, 0) + matrix + u32(64 << 16, 64 << 16))
mdhd = atom('mdhd', u32(0, 0, 0, 600, frames * 600) + u16(0, 0))
hdlr = atom('hdlr', u32(0) + b'mhlrvide' + bytes(12) + b'\x05Video')
vmhd = atom('vmhd', u32(1) + bytes(8))
dref = atom('dref', u32(0, 1) + atom('url ', u32(1)))
dinf = atom('dinf', dref)
sample = bytes(6) + u16(1, 0, 0) + b'appl' + u32(0, 1024) + u16(64, 64) + u32(72 << 16, 72 << 16, 0) + u16(1) + bytes(32) + u16(24, 65535)
stsd = atom('stsd', u32(0, 1) + atom('raw ', sample))
stts = atom('stts', u32(0, 1, frames, 600))
stsc = atom('stsc', u32(0, 1, 1, frames, 1))
stsz = atom('stsz', u32(0, len(frame), frames))
stco = atom('stco', u32(0, 1, len(ftyp) + 8))
stbl = atom('stbl', stsd + stts + stsc + stsz + stco)
minf = atom('minf', vmhd + dinf + stbl)
mdia = atom('mdia', mdhd + hdlr + minf)
trak = atom('trak', tkhd + mdia)
moov = atom('moov', mvhd + trak)
Path(sys.argv[1]).write_bytes(ftyp + mdat + moov)
