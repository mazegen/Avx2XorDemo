# Avx2XorDemo

This project is a minimal “software renderer” demo that lets you **see AVX2 doing useful work in real time**.

It consists of two parts:

- **C++ Win32 window + blitter** (graphics plumbing)
- **MASM AVX2 routine** that fills a pixel buffer (the AVX2 part)

The result is an animated, colorful **XOR pattern** in a window.

---

## What the program does

Every frame (about 60 times per second):

1. It has a memory buffer that represents an image: **W × H pixels**, each pixel is **4 bytes** in **BGRA32** format.
2. Your MASM function `fill_xor_bgra_avx2()` writes new pixel values into that buffer.
3. The C++ code displays that buffer by copying it into the window using **StretchDIBits**.

The animation comes from a time counter `t` that increments every frame and is mixed into the pixel formula.

---

## Why this is a good first “AVX + graphics” demo

- You avoid 3D APIs and GPU concepts.
- You don’t draw primitives. You just write pixels.
- The AVX2 part is very small and obvious:
  - generate 8 pixel values at once
  - store them
- You immediately see if your math works because the window updates live.

---

## The graphics side in plain terms

### The framebuffer

The program allocates a buffer:

- size = `width * height * 4` bytes
- each pixel is 4 bytes: **B, G, R, A**

So pixel `(x,y)` lives at:

- index = `(y * width + x) * 4`
- bytes:
  - `+0` blue
  - `+1` green
  - `+2` red
  - `+3` alpha

### Displaying the buffer

The C++ code sets up a `BITMAPINFO` for a 32-bit top-down image:

- `biBitCount = 32`
- `biCompression = BI_RGB`
- `biHeight = -H` (negative means **top-down** so row 0 is the top of the image)

Then it calls `StretchDIBits(...)` to copy the buffer into the window. That’s the entire “rendering pipeline”.

---

## The AVX2 side: how the assembly works

### Function signature and calling convention

The MASM function is called like:

```c++
fill_xor_bgra_avx2(dst, width, height, t);
```

Windows x64 passes the first 4 args in registers:

- `RCX = dst` (pointer to first pixel)
- `EDX = width`
- `R8D = height`
- `R9D = t` (time)

### The pattern formula

For each pixel:

- compute a value `v` in 0..255:

  `v = (((x + t) & 255) XOR ((y + t) & 255))`

Then colorize it:

- `R = v`
- `G = (v << 1) & 255`
- `B = (v << 2) & 255`
- `A = 255`

This produces moving interference-like bands.

### Why AVX2 helps here

Instead of computing one pixel at a time, the AVX2 loop computes **8 pixels (8 x positions)** in parallel using **8 lanes of 32-bit integers** in one YMM register.

In other words:

- a YMM register is 256 bits
- here we treat it as **8 × 32-bit integers**
- one iteration produces 8 BGRA pixels (8 dwords) and stores them with one store

### The key AVX2 instructions used

- `vpbroadcastd ymmX, xmmY`
  Replicate one 32-bit value into all 8 lanes. Used for `x`, `t`, and `base`.

- `vpaddd ymmA, ymmB, ymmC`
  Add packed 32-bit integers (8 lanes at once). Used for `x + lane`, then `+ t`.

- `vpand ymmA, ymmB, ymmC`
  Bitwise AND on packed dwords. Used to apply `& 255`.

- `vpxor ymmA, ymmB, ymmC`
  XOR on packed dwords. This is the “pattern generator”.

- `vpslld ymmA, ymmB, imm8`
  Shift left dwords. Used to make `v<<1` and `v<<2`.

- `vpor ymmA, ymmB, ymmC`
  OR packed dwords. Used to pack B, G, R into a single 32-bit pixel value.

- `vmovdqu [mem], ymmX`
  Store 32 bytes = **8 pixels**.

- `vzeroupper`
  Clears upper halves to avoid a performance penalty when returning to non-AVX code.

### How 8 pixels are formed and stored

Inside the inner loop:

1. Create `xvec = x + [0..7]`
2. Add time `t` to all lanes
3. Mask to 0..255
4. XOR with `base = (y+t)&255`
5. Create:
   - `G = (v<<1)&255`
   - `B = (v<<2)&255`
   - `R = v`
6. Pack into BGRA dwords:
   - Blue is already in bits 0..7
   - Green is shifted by 8
   - Red is shifted by 16
   - Alpha is `0xFF000000`
7. Store 8 dwords to memory.

The outer loop goes over `y` rows; the inner loop goes over `x` columns.

---

## How to reason about AVX2 here (mental model)

Think of `ymm0` as:

```
ymm0 = [v0 v1 v2 v3 v4 v5 v6 v7]   // 8 independent int32 values
```

Every packed instruction applies the same operation to all lanes. So your scalar formula becomes a “vector formula” almost 1:1.

---

## Common pitfalls to watch for

- **Alignment:** we use `vmovdqu` so the buffer does not need to be aligned.
- **Pixel format order:** Windows 32-bit DIBs with BI_RGB are typically treated as **B,G,R,unused/alpha** in memory. We generate BGRA explicitly.
- **Top-down vs bottom-up:** `biHeight = -H` avoids having to flip the buffer.
- **AVX state transition:** always use `vzeroupper` before returning to code that may use SSE.
