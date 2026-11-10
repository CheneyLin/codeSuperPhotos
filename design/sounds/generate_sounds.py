#!/usr/bin/env python3
"""
生成底部五款销毁道具的短音效 + 切换提示音。

输出：../../../source/appSuperPhotos/SuperPhotos/Resources/Sounds/device_*.wav
格式：PCM 16-bit / 44.1kHz / 单声道，全部本地合成，无外部素材与版权依赖。

用法：python3 design/sounds/generate_sounds.py
重新生成后 Xcode 的 PBXFileSystemSynchronizedRootGroup 会自动把新文件带进 bundle。
"""

import math
import os
import wave
from pathlib import Path

import numpy as np

SR = 44100
RNG = np.random.default_rng(20261110)
OUT = Path(__file__).resolve().parents[2] / "source/appSuperPhotos/SuperPhotos/Resources/Sounds"


def t(duration: float) -> np.ndarray:
    return np.arange(int(SR * duration), dtype=np.float64) / SR


def sine(freq, duration, phase=0.0):
    return np.sin(2 * np.pi * freq * t(duration) + phase)


def exp_decay(duration, tau):
    return np.exp(-t(duration) / tau)


def lowpass(signal, cutoff):
    """一阶低通，用来把白噪声变成闷响 / 气流。"""
    a = math.exp(-2 * math.pi * cutoff / SR)
    out = np.empty_like(signal)
    acc = 0.0
    for i, x in enumerate(signal):
        acc = a * acc + (1 - a) * x
        out[i] = acc
    return out


def highpass(signal, cutoff):
    return signal - lowpass(signal, cutoff)


def burst(duration, start, length, cutoff, gain=1.0, attack=0.004):
    """在 start 秒处放一段带包络的滤波噪声。"""
    buf = np.zeros(int(SR * duration))
    i0 = int(start * SR)
    n = int(length * SR)
    if i0 >= len(buf):
        return buf
    n = min(n, len(buf) - i0)
    noise = RNG.standard_normal(n)
    if cutoff > 0:
        noise = lowpass(noise, cutoff)
    else:
        noise = highpass(noise, -cutoff)
    peak = np.max(np.abs(noise)) or 1.0
    noise /= peak
    env = np.minimum(1.0, np.arange(n) / max(1, SR * attack))
    env *= np.exp(-np.arange(n) / max(1, n / 3.2))
    buf[i0:i0 + n] = noise * env * gain
    return buf


def ping(duration, start, freq, length, gain, harmonics=(1.0, 0.0, 0.0)):
    """在 start 秒处放一个衰减的正弦簇。"""
    buf = np.zeros(int(SR * duration))
    i0 = int(start * SR)
    n = int(length * SR)
    if i0 >= len(buf):
        return buf
    n = min(n, len(buf) - i0)
    tt = np.arange(n) / SR
    env = np.exp(-tt / (length / 3.0)) * np.minimum(1.0, tt / 0.003)
    tone = np.zeros(n)
    for k, amp in enumerate(harmonics, start=1):
        if amp:
            tone += amp * np.sin(2 * np.pi * freq * k * tt)
    buf[i0:i0 + n] = tone * env * gain
    return buf


def finish(signal, peak=0.82, fade=0.006):
    """统一归一化 + 头尾淡入淡出，避免 AVAudioPlayer 起播爆音。"""
    signal = np.asarray(signal, dtype=np.float64)
    m = np.max(np.abs(signal)) or 1.0
    signal = signal / m * peak
    n = min(int(SR * fade), len(signal) // 2)
    if n > 0:
        ramp = np.linspace(0, 1, n)
        signal[:n] *= ramp
        signal[-n:] *= ramp[::-1]
    return signal


def write(name, signal):
    OUT.mkdir(parents=True, exist_ok=True)
    data = (np.clip(signal, -1, 1) * 32767).astype("<i2").tobytes()
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(data)
    print(f"{path.name:26s} {len(signal)/SR:.2f}s  {len(data)//1024}KB")


# 1) 切换：极短的两段上行"嗒"，不抢戏。
def device_switch():
    d = 0.17
    s = ping(d, 0.0, 720, 0.07, 0.55, (1.0, 0.18, 0.06))
    s += ping(d, 0.055, 960, 0.09, 0.42, (1.0, 0.12, 0.0))
    s += burst(d, 0.0, 0.02, -2600, 0.22)
    return finish(s, peak=0.6)


# 2) 废纸篓：纸团摩擦 + 落入桶底的闷响。
def device_bin():
    d = 0.50
    s = np.zeros(int(SR * d))
    for start, length, gain in [(0.0, 0.10, 0.42), (0.075, 0.09, 0.36), (0.15, 0.12, 0.28)]:
        s += burst(d, start, length, -1500, gain)
    s += ping(d, 0.20, 128, 0.24, 0.55, (1.0, 0.35, 0.12))
    s += burst(d, 0.20, 0.13, 520, 0.45)
    return finish(s)


# 3) 碎纸机：马达起停 + 滚轮摩擦 + 纸屑切断声。
def device_shredder():
    d = 0.62
    tt = t(d)
    ramp = np.minimum(1.0, tt / 0.07) * np.minimum(1.0, (d - tt) / 0.10)
    ramp = np.clip(ramp, 0, 1)
    motor = sum(
        amp * np.sin(2 * np.pi * (78 * k) * tt + 0.4 * np.sin(2 * np.pi * 5 * tt))
        for k, amp in [(1, 0.55), (2, 0.24), (3, 0.13), (5, 0.06)]
    )
    grind = lowpass(RNG.standard_normal(len(tt)), 2100)
    grind /= np.max(np.abs(grind)) or 1.0
    s = 0.62 * motor * ramp + 0.26 * grind * ramp
    for start in (0.10, 0.25, 0.40, 0.52):
        s += burst(d, start, 0.035, -3200, 0.24)
    return finish(s)


# 4) 壁炉：气流上涌 + 木柴爆裂 + 低频余温。
def device_fireplace():
    d = 0.78
    tt = t(d)
    air = lowpass(RNG.standard_normal(len(tt)), 900)
    air /= np.max(np.abs(air)) or 1.0
    swell = np.sin(np.pi * np.clip(tt / 0.55, 0, 1)) ** 1.4
    s = 0.42 * air * swell
    s += 0.20 * np.sin(2 * np.pi * 62 * tt) * exp_decay(d, 0.30)
    for i in range(11):
        start = 0.04 + RNG.random() * 0.60
        s += burst(d, float(start), 0.018 + float(RNG.random()) * 0.022,
                   -3000, 0.20 + float(RNG.random()) * 0.20)
    return finish(s)


# 5) 邮筒：金属投口"啪"两下 + 信件滑入 + 小铃。
def device_mailbox():
    d = 0.56
    s = ping(d, 0.00, 380, 0.09, 0.52, (1.0, 0.42, 0.18))
    s += burst(d, 0.00, 0.045, -2200, 0.34)
    s += burst(d, 0.09, 0.13, -1700, 0.26)
    s += ping(d, 0.16, 210, 0.13, 0.38, (1.0, 0.3, 0.0))
    s += ping(d, 0.24, 1180, 0.28, 0.30, (1.0, 0.24, 0.08))
    return finish(s)


# 6) 任意门：开门低频 + 上行铃音琶音 + 空气感。
def device_door():
    d = 0.74
    tt = t(d)
    s = 0.22 * np.sin(2 * np.pi * (110 - 45 * np.clip(tt / 0.4, 0, 1)) * tt) * exp_decay(d, 0.22)
    whoosh = lowpass(RNG.standard_normal(len(tt)), 1400)
    whoosh /= np.max(np.abs(whoosh)) or 1.0
    s += 0.20 * whoosh * np.sin(np.pi * np.clip(tt / d, 0, 1))
    for i, freq in enumerate((523.25, 659.25, 783.99, 1046.50)):
        s += ping(d, 0.06 + i * 0.075, freq, 0.34, 0.26, (1.0, 0.30, 0.10))
    return finish(s)


if __name__ == "__main__":
    write("device_switch", device_switch())
    write("device_bin", device_bin())
    write("device_shredder", device_shredder())
    write("device_fireplace", device_fireplace())
    write("device_mailbox", device_mailbox())
    write("device_door", device_door())
    print(f"输出目录：{OUT}")
