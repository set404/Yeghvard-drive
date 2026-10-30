"""Voices for the story's lines, made with Kokoro (a free neural text-to-speech
model): every line said in missions/*.gd (Dialogue.say, talk.bark and the
shout lists) gets an .ogg in audio/voices/, named after its speaker and text
(game/dialogue.gd finds it the same way). Lines with no file are mumbled.

Needs:  pip install kokoro-onnx soundfile   and ffmpeg, plus the model files
kokoro-v1.0.int8.onnx and voices-v1.0.bin from
https://github.com/thewh1teagle/kokoro-onnx/releases (model-files-v1.0)
next to this script.

Run:  python tools/make_voices.py      (only makes the files that are missing;
      --all makes them all again)
"""
import hashlib, os, re, subprocess, sys, tempfile
import soundfile as sf
from kokoro_onnx import Kokoro

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "audio", "voices")

# Speaker -> Kokoro voice, speed, and ffmpeg filters for their sound.
VOICES = {
    "Vzgo": ("am_michael", 1.0, ""),
    "Davitik": ("am_puck", 1.08, ""),
    "Uncle": ("bm_george", 0.9, "asetrate=24000*0.88,aresample=24000,atempo=1.08"),
    "Papa": ("am_onyx", 0.95, ""),
}
# Over the phone: a phone's narrow band.
PHONE = "highpass=f=320,lowpass=f=3200,acrusher=bits=10:mix=0.25"
# How the Armenian words are said (the subtitles keep them as written).
SAY_AS = [
    (r"\bGyada jan\b", "Gyahdah jahn"), (r"\bgyada\b", "gyahdah"), (r"\bGyada\b", "Gyahdah"),
    (r"\buncle jan\b", "uncle jahn"), (r"\bloqsh\b", "lohksh"), (r"\bhayat\b", "hah-yaht"),
    (r"\btgha\b", "tuh-ghah"), (r"\bDuets\b", "Doo-ets"), (r"\bDuet\b", "Doo-et"),
    (r"\bDavitik\b", "Dahveeteek"), (r"\baraaa\b", "ahrahhh"), (r"\bARA\b", "AHRAH"),
    (r"\bara\b", "ahrah"), (r"\bAra\b", "Ahrah"), (r"(HA ?){3,}", "Ha ha ha ha ha! "),
    (r"\*[^*]*\*", ""),
]


def key(who, text):
    return "%s_%s" % (who.lower(), hashlib.md5(("%s|%s" % (who, text)).encode("utf-8")).hexdigest()[:10])


def lines():
    """(who, text, phone) for every line in the missions."""
    found = []
    for name in sorted(os.listdir(os.path.join(ROOT, "missions"))):
        if not name.endswith(".gd"):
            continue
        src = open(os.path.join(ROOT, "missions", name), encoding="utf-8").read()
        for m in re.finditer(r'Dialogue\.say\("([^"]*)",\s*"((?:[^"\\]|\\.)*)"([^)]*)\)', src):
            who, text, rest = m.group(1), m.group(2).replace('\\"', '"'), m.group(3)
            if who and not (text.startswith("*") and text.endswith("*")):
                found.append((who, text, "true" in rest))
        for m in re.finditer(r'talk\.bark\("([^"]+)",\s*"((?:[^"\\]|\\.)*)"', src):
            found.append((m.group(1), m.group(2), False))
        # Shout lists: SLAP_LINES / CAR_HIT_LINES (Davitik's).
        for m in re.finditer(r'const (\w+_LINES) := \[(.*?)\]', src):
            for t in re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(2)):
                found.append(("Davitik", t, False))
    # Kokoro cannot say Armenian letters: those lines are recorded by people.
    found = [f for f in found if not re.search("[԰-֏]", f[1])]
    return list(dict.fromkeys(found))


def main():
    again = "--all" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    tts = Kokoro(os.path.join(HERE, "kokoro-v1.0.int8.onnx"), os.path.join(HERE, "voices-v1.0.bin"))
    made = 0
    for who, text, phone in lines():
        name = key(who, text) + ("_phone" if phone else "") + ".ogg"
        path = os.path.join(OUT, name)
        if os.path.exists(path) and not again:
            continue
        voice, speed, sound = VOICES.get(who, VOICES["Vzgo"])
        spoken = text
        for pattern, said in SAY_AS:
            spoken = re.sub(pattern, said, spoken)
        spoken = spoken.strip() or text
        shouting = text.upper() == text and len(text) > 4
        audio, rate = tts.create(spoken, voice=voice, speed=speed * (1.08 if shouting else 1.0), lang="en-us")
        filters = [f for f in [sound, PHONE if phone else "", "volume=1.6" if shouting else ""] if f]
        filters.append("loudnorm=I=-16:TP=-1.5")
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            sf.write(tmp.name, audio, rate)
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp.name, "-af", ",".join(filters),
                        "-c:a", "libvorbis", "-q:a", "4", path], check=True)
        os.unlink(tmp.name)
        made += 1
        print("%-8s %-58s -> %s" % (who, text[:58], name))
    print("%d made, in %s" % (made, OUT))


if __name__ == "__main__":
    main()
