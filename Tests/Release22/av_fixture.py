"""20-second native QuickTime fixture with raw video and a real silent PCM audio track."""
import runpy,sys
from pathlib import Path
n=runpy.run_path('Tests/PlaybackSession39/video_fixture.py')
u32,u16,atom=n['u32'],n['u16'],n['atom'];rate=8000;count=20*rate
sample=bytes(6)+u16(1,0,0)+u32(0)+u16(1,16,0,0)+u32(rate<<16)
stsd=atom('stsd',u32(0,1)+atom('sowt',sample))
stts=atom('stts',u32(0,1,count,1));stsc=atom('stsc',u32(0,1,1,count,1));stsz=atom('stsz',u32(0,2,count));stco=atom('stco',u32(0,1,len(n['ftyp'])+len(n['mdat'])))
stbl=atom('stbl',stsd+stts+stsc+stsz+stco)
minf=atom('minf',atom('smhd',u32(0)+u16(0,0))+n['dinf']+stbl)
mdhd=atom('mdhd',u32(0,0,0,rate,count)+u16(0,0));hdlr=atom('hdlr',u32(0)+b'mhlrsoun'+bytes(12)+b'\x05Sound')
mdia=atom('mdia',mdhd+hdlr+minf)
tkhd=atom('tkhd',u32(7,0,0,2,0,20*600)+bytes(8)+u16(0,0,256,0)+n['matrix']+u32(0,0))
mdat=atom('mdat',n['mdat'][8:]+bytes(count*2));moov=atom('moov',n['mvhd'][:-4]+u32(3)+n['trak']+atom('trak',tkhd+mdia))
Path(sys.argv[1]).write_bytes(n['ftyp']+mdat+moov)
