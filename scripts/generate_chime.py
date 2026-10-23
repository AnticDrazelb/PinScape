#!/usr/bin/env python3
"""Synthesises Pinscape's "pin dropped" chime: two soft bell notes a fifth apart.

    python3 scripts/generate_chime.py
"""
import math
import os
import struct
import wave

RATE = 44_100
OUT = os.path.join(os.path.dirname(__file__), "..", "Pinscape", "Resources", "Sounds", "PinDrop.wav")


def bell(frequency, start, length, gain):
    """A struck-bell tone: fundamental plus a couple of soft partials, fast attack, smooth decay."""
    partials = [(1.0, 1.0), (2.0, 0.28), (3.01, 0.08)]
    samples = {}
    for i in range(int(length * RATE)):
        t = i / RATE
        attack = min(1.0, t / 0.004)
        decay = math.exp(-t / 0.11)
        value = sum(amp * math.sin(2 * math.pi * frequency * ratio * t) for ratio, amp in partials)
        samples[int(start * RATE) + i] = value * attack * decay * gain
    return samples


def main():
    total = int(0.42 * RATE)
    mix = [0.0] * total
    for tone in (bell(1046.5, 0.0, 0.32, 0.33), bell(1568.0, 0.075, 0.34, 0.30)):  # C6, then G6
        for index, value in tone.items():
            if index < total:
                mix[index] += value
    # Gentle fade so the tail never clicks.
    for i in range(int(0.05 * RATE)):
        mix[total - 1 - i] *= i / (0.05 * RATE)
    peak = max(abs(v) for v in mix)
    scale = 0.5 / peak  # about -6 dBFS
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with wave.open(OUT, "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(b"".join(struct.pack("<h", int(v * scale * 32767)) for v in mix))
    print("Wrote", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
