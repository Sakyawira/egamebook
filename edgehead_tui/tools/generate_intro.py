"""Generate the original looping forest intro used by the TUI.

Requires Python 3 and ffmpeg. Run from any directory.
"""

from array import array
import math
from pathlib import Path
import subprocess
import tempfile
import wave


RATE = 44_100
DURATION = 16
CHORDS = (
    (146.83, 174.61, 220.00),  # D minor
    (116.54, 146.83, 174.61),  # B flat
    (87.31, 110.00, 130.81),  # F major
    (130.81, 164.81, 196.00),  # C major
)
OUTPUT = Path(__file__).resolve().parents[1] / "assets/audio/forest_intro.m4a"


def chord_sample(chord, time):
    return sum(
        math.sin(2 * math.pi * frequency * time) * 0.5
        + math.sin(2 * math.pi * frequency * 2 * time) * 0.08
        for frequency in chord
    ) / len(chord)


def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    samples = array("h")
    for index in range(RATE * DURATION):
        time = index / RATE
        section = int(time // 4)
        section_time = time % 4
        blend = min(1.0, section_time / 0.45)
        pad = (
            chord_sample(CHORDS[(section - 1) % 4], time) * (1 - blend)
            + chord_sample(CHORDS[section], time) * blend
        )
        beat = int(time / 0.5)
        beat_time = time % 0.5
        note = CHORDS[(beat // 8) % 4][beat % 3] * 2
        pluck = math.exp(-beat_time * 9) * (
            math.sin(2 * math.pi * note * time)
            + 0.25 * math.sin(2 * math.pi * note * 2 * time)
        )
        fade = min(1.0, time / 0.1, (DURATION - time) / 0.1)
        amplitude = fade * (0.40 * pad + 0.13 * pluck)
        samples.append(int(max(-1.0, min(1.0, amplitude)) * 32767))

    with tempfile.TemporaryDirectory(prefix="edgehead-intro-") as directory:
        wav_path = Path(directory) / "forest_intro.wav"
        with wave.open(str(wav_path), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(RATE)
            wav.writeframes(samples.tobytes())
        subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-i", str(wav_path), "-c:a", "aac", "-b:a", "96k",
                str(OUTPUT),
            ],
            check=True,
        )
    print(OUTPUT)


if __name__ == "__main__":
    main()
