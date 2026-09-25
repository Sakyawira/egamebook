"""Generate the original haunting intro loop used by the TUI.

Requires Python 3 and ffmpeg. Run from any directory.
"""

from array import array
import math
import random
from pathlib import Path
import subprocess
import tempfile
import wave


RATE = 44_100
DURATION = 32
TWO_PI = 2 * math.pi
OUTPUT = Path(__file__).resolve().parents[1] / "assets/audio/thrilling.m4a"

# D grinds against a flattened, slightly-detuned A-flat (a tritone instead of
# the old minor second) so the high notes feel wrong rather than just sour.
# The high notes are still sparse so the track can loop under narration
# without competing with it.
BELLS = (
    (2.0, 587.33),   # D5
    (6.8, 415.30),   # A-flat4 (tritone below D5)
    (11.5, 440.00),  # A4
    (16.2, 523.25),  # C5
    (21.0, 415.30),  # A-flat4
    (25.7, 587.33),  # D5
)
PULSES = (4.0, 4.38, 12.0, 12.38, 20.0, 20.38, 28.0, 28.38)

# Sparse, irregular "something moved" stingers. Kept off-grid from PULSES so
# they read as an intrusion rather than part of the rhythm.
JUMP_SCARES = (9.4, 18.9, 27.3)

# A slow sub-bass throb sitting just above the threshold of feeling-not-
# hearing it, like a heartbeat under the floorboards.
HEARTBEAT_HZ = 0.82


def sample_at(time, wind, whisper):
    swell = 0.75 + 0.25 * math.sin(TWO_PI * time / 13)

    # Slow, almost imperceptible pitch drift on the drone fundamentals so
    # the tone never quite settles -- classic "something's off" unease.
    drift = 1.0 + 0.004 * math.sin(TWO_PI * time / 21)

    drone = swell * (
        0.17 * math.sin(TWO_PI * 73.42 * drift * time)
        + 0.13 * math.sin(TWO_PI * 69.30 * drift * time)  # was 73.68: widened to a beating minor 2nd
        + 0.08 * math.sin(TWO_PI * 36.71 * drift * time)
        + 0.055 * math.sin(TWO_PI * 146.83 * time + 0.5 * math.sin(time / 3))
        + 0.035 * math.sin(TWO_PI * 155.56 * time)
    )

    # Heartbeat: two quick sub-bass thumps per cycle (lub-dub), amplitude
    # modulated so it breathes in and out of audibility.
    beat_phase = (time * HEARTBEAT_HZ) % 1.0
    heartbeat = 0.0
    for offset, strength in ((0.0, 1.0), (0.16, 0.6)):
        local = (beat_phase - offset) % 1.0
        if local < 0.12:
            heartbeat += strength * math.exp(-local * 40) * math.sin(TWO_PI * 55 * time)
    heartbeat *= 0.05 * (0.6 + 0.4 * math.sin(TWO_PI * time / 27))

    bells = 0.0
    for onset, frequency in BELLS:
        age = time - onset
        if 0 <= age < 5:
            envelope = min(1.0, age / 0.04) * math.exp(-age * 0.85)
            bells += envelope * (
                0.075 * math.sin(TWO_PI * frequency * age)
                + 0.03 * math.sin(TWO_PI * frequency * 2.756 * age)  # inharmonic partial, not a clean overtone
                + 0.018 * math.sin(TWO_PI * frequency * 4.42 * age)  # -> reads as glassy/wrong rather than musical
                # slight detuned unison for a metallic, slightly wrong shimmer
                + 0.02 * math.sin(TWO_PI * frequency * 1.006 * age)
            )

    pulse = 0.0
    for onset in PULSES:
        age = time - onset
        if 0 <= age < 0.45:
            pulse += 0.10 * math.exp(-age * 15) * math.sin(
                TWO_PI * (53 * age - 16 * age * age)
            )

    # Jump scares: fast upward-shrieking transient with noise bite, over
    # almost as soon as it registers.
    scare = 0.0
    for onset in JUMP_SCARES:
        age = time - onset
        if 0 <= age < 0.35:
            chirp = math.sin(TWO_PI * (180 * age + 900 * age * age))
            scare += 0.22 * math.exp(-age * 9) * (0.7 * chirp + 0.3 * whisper)

    # Whispery breath: same slow wind envelope as before, but the noise
    # feeds through a rough formant-ish comb to sound closer to breathing
    # or a voice under threshold than plain air.
    breath = 0.10 * wind * (0.6 + 0.4 * math.sin(TWO_PI * time / 9))
    breath += 0.03 * whisper * (0.5 + 0.5 * math.sin(TWO_PI * time / 5.3))

    return drone + heartbeat + bells + pulse + scare + breath


def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    samples = array("h")
    seed = 0xEC0DE
    rng = random.Random(0xBADF00D)
    wind = 0.0
    whisper_raw = 0.0
    whisper = 0.0
    for index in range(RATE * DURATION):
        time = index / RATE
        seed = (1664525 * seed + 1013904223) & 0xFFFFFFFF
        noise = ((seed >> 16) / 32767.5) - 1
        wind += 0.025 * (noise - wind)

        # Second, faster noise source run through a narrower smoothing
        # window and a mild formant-style resonance so it reads as a
        # breathy, almost-voice texture rather than plain hiss.
        whisper_raw += 0.35 * (rng.uniform(-1, 1) - whisper_raw)
        whisper += 0.08 * (whisper_raw - whisper)
        whisper += 0.015 * math.sin(TWO_PI * 420 * time) * abs(whisper)

        fade = min(1.0, time / 0.8, (DURATION - time) / 0.8)
        amplitude = math.tanh(sample_at(time, wind, whisper) * fade * 1.5)
        samples.append(int(amplitude * 32767))

    with tempfile.TemporaryDirectory(prefix="edgehead-intro-") as directory:
        wav_path = Path(directory) / "thrilling_intro.wav"
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
                    # Longer, denser echo tail for a cavernous, unnatural space
                    "aecho=0.7:0.3:520|980|1650:0.35|0.22|0.12,"
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
