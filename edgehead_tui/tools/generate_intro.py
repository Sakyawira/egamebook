"""Generate the original haunting intro loop used by the TUI.

Requires Python 3 and ffmpeg. Run from any directory.
"""

from array import array
import math
from pathlib import Path
import subprocess
import tempfile
import wave


RATE = 44_100
DURATION = 32
TWO_PI = 2 * math.pi
OUTPUT = Path(__file__).resolve().parents[1] / "assets/audio/haunting_intro.m4a"

# D and E-flat rub against each other over the low drone. The high notes are
# sparse so the track can loop under narration without competing with it.
BELLS = (
    (2.0, 587.33),   # D5
    (6.8, 622.25),   # E-flat5
    (11.5, 440.00),  # A4
    (16.2, 523.25),  # C5
    (21.0, 622.25),  # E-flat5
    (25.7, 587.33),  # D5
)
PULSES = (4.0, 4.38, 12.0, 12.38, 20.0, 20.38, 28.0, 28.38)


def sample_at(time, wind):
    swell = 0.75 + 0.25 * math.sin(TWO_PI * time / 13)
    drone = swell * (
        0.17 * math.sin(TWO_PI * 73.42 * time)
        + 0.13 * math.sin(TWO_PI * 73.68 * time)
        + 0.06 * math.sin(TWO_PI * 36.71 * time)
        + 0.055 * math.sin(TWO_PI * 146.83 * time + 0.3 * math.sin(time / 4))
        + 0.035 * math.sin(TWO_PI * 155.56 * time)
    )

    bells = 0.0
    for onset, frequency in BELLS:
        age = time - onset
        if 0 <= age < 5:
            envelope = min(1.0, age / 0.04) * math.exp(-age * 0.9)
            bells += envelope * (
                0.075 * math.sin(TWO_PI * frequency * age)
                + 0.025 * math.sin(TWO_PI * frequency * 2.01 * age)
                + 0.012 * math.sin(TWO_PI * frequency * 3.91 * age)
            )

    pulse = 0.0
    for onset in PULSES:
        age = time - onset
        if 0 <= age < 0.45:
            pulse += 0.10 * math.exp(-age * 15) * math.sin(
                TWO_PI * (53 * age - 16 * age * age)
            )

    breath = 0.09 * wind * (0.65 + 0.35 * math.sin(TWO_PI * time / 9))
    return drone + bells + pulse + breath


def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    samples = array("h")
    seed = 0xEC0DE
    wind = 0.0
    for index in range(RATE * DURATION):
        time = index / RATE
        seed = (1664525 * seed + 1013904223) & 0xFFFFFFFF
        noise = ((seed >> 16) / 32767.5) - 1
        wind += 0.025 * (noise - wind)
        fade = min(1.0, time / 0.8, (DURATION - time) / 0.8)
        amplitude = math.tanh(sample_at(time, wind) * fade * 1.4)
        samples.append(int(amplitude * 32767))

    with tempfile.TemporaryDirectory(prefix="edgehead-intro-") as directory:
        wav_path = Path(directory) / "haunting_intro.wav"
        with wave.open(str(wav_path), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(RATE)
            wav.writeframes(samples.tobytes())
        subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-i", str(wav_path),
                "-af", (
                    "aecho=0.65:0.22:640|1270:0.30|0.15,"
                    f"atrim=duration={DURATION},"
                    "afade=t=in:st=0:d=0.8,"
                    f"afade=t=out:st={DURATION - 0.8}:d=0.8"
                ),
                "-c:a", "aac", "-b:a", "128k", str(OUTPUT),
            ],
            check=True,
        )
    print(OUTPUT)


if __name__ == "__main__":
    main()
