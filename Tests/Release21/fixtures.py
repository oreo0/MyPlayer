import sys,wave,math,struct,subprocess
from pathlib import Path
p=Path(sys.argv[1]);p.mkdir(parents=True,exist_ok=True)
with wave.open(str(p/'source.wav'),'wb') as f:
 f.setparams((1,2,22050,0,'NONE','not compressed'))
 f.writeframes(b''.join(struct.pack('<h',int(1800*math.sin(i*440*math.tau/22050))) for i in range(22050*3)))
for ext,fmt,codec in [('aiff','AIFF','BEI16'),('flac','flac','flac'),('m4a','m4af','aac '),('mp4','mp4f','aac ')]:
 subprocess.run(['/usr/bin/afconvert','-f',fmt,'-d',codec,str(p/'source.wav'),str(p/('source.'+ext))],check=True)
# MPEG-1 Layer III mono, 128kbps/44.1kHz, zeroed side information and main data.
(p/'source.mp3').write_bytes((bytes.fromhex('fffb90c4')+bytes(413))*120)
subprocess.run([sys.executable,'Tests/PlaybackSession39/video_fixture.py',str(p/'source.mov')],check=True)
