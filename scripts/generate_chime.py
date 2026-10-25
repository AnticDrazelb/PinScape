#!/usr/bin/env python3
"""Synthesises Pinscape's sounds:

- PinDrop.wav, "pin dropped": two soft bell notes a fifth apart.
- Arrival.wav, "you're here": a brighter rising arpeggio, played twice, loud enough to notice in a
  pocket. It's the arrival notification's sound.

    python3 scripts/generate_chime.py
"""
import math
import os
import struct
import wave

RATE = 44_100
SOUNDS = os.path.join(os.path.dirname(__file__), "..", "Pinscape", "Resources", "Sounds")


def bell(frequency, start, length, gain, decay=0.11):
    """A struck-bell tone: fundamental plus a couple of soft partials, fast attack, smooth decay."""
    partials = [(1.0, 1.0), (2.0, 0.28), (3.01, 0.08)]
    samples = {}
    for i in range(int(length * RATE)):
        t = i / RATE
        attack = min(1.0, t / 0.004)
        envelope = math.exp(-t / decay)
        value = sum(amp * math.sin(2 * math.pi * frequency * ratio * t) for ratio, amp in partials)
        samples[int(start * RATE) + i] = value * attack * envelope * gain
    return samples


def render(name, duration, tones, peak):
    total = int(duration * RATE)
    mix = [0.0] * total
    for tone in tones:
        for index, value in tone.items():
            if index < total:
                mix[index] += value
    # Gentle fade so the tail never clicks.
    for i in range(int(0.05 * RATE)):
        mix[total - 1 - i] *= i / (0.05 * RATE)
    scale = peak / max(abs(v) for v in mix)
    path = os.path.join(SOUNDS, name)
    os.makedirs(SOUNDS, exist_ok=True)
    with wave.open(path, "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(b"".join(struct.pack("<h", int(v * scale * 32767)) for v in mix))
    print("Wrote", os.path.abspath(path))


def main():
    # C6, then G6, at about -6 dBFS.
    render("PinDrop.wav", 0.42, [bell(1046.5, 0.0, 0.32, 0.33), bell(1568.0, 0.075, 0.34, 0.30)], peak=0.5)

    # G5 C6 E6 G6, twice, at about -2 dBFS.
    arpeggio = [(784.0, 0.0), (1046.5, 0.11), (1318.5, 0.22), (1568.0, 0.33)]
    tones = []
    for repeat in (0.0, 0.8):
        for index, (frequency, offset) in enumerate(arpeggio):
            last = index == len(arpeggio) - 1
            tones.append(bell(frequency, repeat + offset, 0.75 if last else 0.4, 0.3, decay=0.28 if last else 0.16))
    render("Arrival.wav", 1.9, tones, peak=0.8)


if __name__ == "__main__":
    main()
