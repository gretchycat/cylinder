#!/usr/bin/env python3
"""
generate_end_cap_rib_texture.py
--------------------------------
Generates a high-fidelity weathered industrial "old rib" texture for the
O'Neill cylinder hemispherical end cap bulkheads.

Features:
- Heavy structural I-beam rib flanges with bevels and edge wear.
- Concentric cross-stiffeners and reinforced gusset plates.
- Corrugated / fluted alloy sheet metal paneling in recessed bays.
- Rows of industrial aerospace rivets and heavy bolt fasteners.
- Aged, weathered patina: multi-octave oxidation, soot, grease staining, and scuffed bare alloy.
- Industrial warning stencils and amber maintenance hazard stripes.
- Seamless horizontal and vertical tiling.
"""

import math
import random
from PIL import Image

def generate_rib_texture(
    width: int = 1024,
    height: int = 1024,
    output_path: str = "assets/textures/terrain/end_cap_ribs.png",
    seed: int = 77
):
    rng = random.Random(seed)
    img = Image.new("RGB", (width, height))

    # Base industrial color palette (dark weathered aerospace alloy & primer)
    c_primer_dark   = (42, 45, 52)      # Deep oxidized primer in recesses
    c_primer_mid    = (58, 62, 70)      # Base bulkhead alloy
    c_rib_face      = (72, 78, 88)      # Structural rib top face
    c_scuff_alloy   = (175, 185, 198)   # Exposed bare worn alloy on raised edges
    c_crevice_dirt  = (22, 24, 28)      # Ambient occlusion / grease in seams
    c_oxide_rust    = (78, 54, 42)      # Subtle warm oxide patina in corners
    c_rivet         = (145, 155, 168)   # Metal rivet heads
    c_hazard_amber  = (185, 138, 42)    # Aged industrial safety markings

    # Generate multi-octave noise tables for seamless organic patina
    noise_res = 128
    perm = list(range(256))
    rng.shuffle(perm)
    perm += perm

    def grad(h, x, y):
        h = h & 7
        u = x if h < 4 else y
        v = y if h < 4 else x
        return (u if (h & 1) == 0 else -u) + (v if (h & 2) == 0 else -v)

    def perlin(x, y):
        xi = int(x) & 255
        yi = int(y) & 255
        xf = x - int(x)
        yf = y - int(y)
        u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
        v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
        aa = perm[perm[xi] + yi]
        ab = perm[perm[xi] + yi + 1]
        ba = perm[perm[xi + 1] + yi]
        bb = perm[perm[xi + 1] + yi + 1]
        x1 = (1 - u) * grad(aa, xf, yf) + u * grad(ba, xf - 1, yf)
        x2 = (1 - u) * grad(ab, xf, yf - 1) + u * grad(bb, xf - 1, yf - 1)
        return (1 - v) * x1 + v * x2

    def seamless_noise(u, v, scale):
        # 4D torus sampling for perfectly seamless periodic noise
        r = scale / (2.0 * math.pi)
        theta = u * math.tau
        phi = v * math.tau
        nx = r * math.cos(theta) + 100.0
        ny = r * math.sin(theta) + 100.0
        nz = r * math.cos(phi) + 100.0
        nw = r * math.sin(phi) + 100.0
        n1 = perlin(nx, ny)
        n2 = perlin(nz, nw)
        return (n1 + n2) * 0.5

    # Texture layout dimensions (repeats seamlessly)
    num_rib_cols = 4   # 4 major vertical ribs across the tile
    num_cross_rows = 4 # 4 horizontal cross-stiffeners across the tile

    col_pitch = width / num_rib_cols
    row_pitch = height / num_cross_rows
    rib_half_w = col_pitch * 0.14
    cross_half_h = row_pitch * 0.12

    pixels = []

    for y in range(height):
        v = float(y) / float(height)
        y_in_cell = y % row_pitch
        dist_y_cross = abs(y_in_cell - row_pitch * 0.5)

        for x in range(width):
            u = float(x) / float(width)
            x_in_cell = x % col_pitch
            dist_x_rib = abs(x_in_cell - col_pitch * 0.5)

            # 1. Structural Rib Profile (Vertical major ribs)
            is_on_rib = dist_x_rib <= rib_half_w
            is_rib_edge = abs(dist_x_rib - rib_half_w) <= 3.5

            # 2. Concentric Cross-Stiffeners (Horizontal girders)
            is_on_cross = dist_y_cross <= cross_half_h
            is_cross_edge = abs(dist_y_cross - cross_half_h) <= 3.0

            # 3. Fluted / Corrugated Panel Webbing (in recessed bays between ribs)
            corrugation = 0.0
            if not is_on_rib and not is_on_cross:
                flute_freq = 18.0 # 18 flutes per cell
                flute_x = (dist_x_rib - rib_half_w) / (col_pitch * 0.5 - rib_half_w)
                corrugation = math.sin(flute_x * math.pi * flute_freq) * 0.5 + 0.5

            # 4. Rivet / Fastener Placement along rib flanges
            is_rivet = False
            is_rivet_rim = False
            rivet_spacing = row_pitch / 8.0 # 8 rivets per bay
            rivet_y_rel = abs((y % rivet_spacing) - rivet_spacing * 0.5)

            # Left and right rivet lines along the rib flange
            for flange_offset in [-rib_half_w * 0.65, rib_half_w * 0.65]:
                dx_riv = abs((x_in_cell - col_pitch * 0.5) - flange_offset)
                dist_riv = math.sqrt(dx_riv * dx_riv + rivet_y_rel * rivet_y_rel)
                if dist_riv <= 3.8:
                    is_rivet = True
                elif dist_riv <= 5.2:
                    is_rivet_rim = True

            # 5. Natural Aged Weathering / Grime / Metal Patina
            n_macro = seamless_noise(u, v, 4.0)
            n_micro = seamless_noise(u, v, 16.0)
            n_fine  = seamless_noise(u, v, 48.0)
            patina  = n_macro * 0.50 + n_micro * 0.35 + n_fine * 0.15

            # Base color computation
            if is_on_rib or is_on_cross:
                # Structural rib surface
                blend = (dist_x_rib / rib_half_w) if is_on_rib else (dist_y_cross / cross_half_h)
                r_base = c_rib_face[0] * (1.0 - blend * 0.25) + c_primer_mid[0] * (blend * 0.25)
                g_base = c_rib_face[1] * (1.0 - blend * 0.25) + c_primer_mid[1] * (blend * 0.25)
                b_base = c_rib_face[2] * (1.0 - blend * 0.25) + c_primer_mid[2] * (blend * 0.25)

                # Edge scuffing / worn alloy highlight along rib corners
                if is_rib_edge or is_cross_edge:
                    scuff_amt = 0.65 + 0.35 * n_fine
                    r_base = r_base * (1.0 - scuff_amt) + c_scuff_alloy[0] * scuff_amt
                    g_base = g_base * (1.0 - scuff_amt) + c_scuff_alloy[1] * scuff_amt
                    b_base = b_base * (1.0 - scuff_amt) + c_scuff_alloy[2] * scuff_amt

                # Intersection gusset reinforcement (where cross meets rib)
                if is_on_rib and is_on_cross:
                    r_base *= 1.12
                    g_base *= 1.12
                    b_base *= 1.15
            else:
                # Recessed bay paneling
                panel_depth = 1.0 - (dist_x_rib / (col_pitch * 0.5))
                r_base = c_primer_dark[0] * (0.8 + 0.3 * corrugation)
                g_base = c_primer_dark[1] * (0.8 + 0.3 * corrugation)
                b_base = c_primer_dark[2] * (0.8 + 0.3 * corrugation)

                # Ambient occlusion crease shadow right against the rib wall
                if dist_x_rib < rib_half_w + 8.0 or dist_y_cross < cross_half_h + 8.0:
                    r_base = r_base * 0.65 + c_crevice_dirt[0] * 0.35
                    g_base = g_base * 0.65 + c_crevice_dirt[1] * 0.35
                    b_base = b_base * 0.65 + c_crevice_dirt[2] * 0.35

                # Subtle oxidized rust staining in recessed corners
                if (dist_x_rib < rib_half_w + 14.0) and (dist_y_cross < cross_half_h + 14.0):
                    rust_factor = max(0.0, 0.45 * (n_micro + 0.2))
                    r_base = r_base * (1.0 - rust_factor) + c_oxide_rust[0] * rust_factor
                    g_base = g_base * (1.0 - rust_factor) + c_oxide_rust[1] * rust_factor
                    b_base = b_base * (1.0 - rust_factor) + c_oxide_rust[2] * rust_factor

            # Rivet highlights & shadow rims
            if is_rivet:
                r_base = c_rivet[0] * 1.15
                g_base = c_rivet[1] * 1.15
                b_base = c_rivet[2] * 1.18
            elif is_rivet_rim:
                r_base = c_crevice_dirt[0] * 0.8
                g_base = c_crevice_dirt[1] * 0.8
                b_base = c_crevice_dirt[2] * 0.8

            # Industrial warning hazard stripe accent on selective cross-beams
            if is_on_cross and (int(y / row_pitch) % 2 == 1):
                # Diagonal hazard angle
                stripe = ((x + y * 1.2) % 40.0) / 40.0
                if stripe > 0.5:
                    h_factor = 0.55 + 0.25 * n_fine
                    r_base = r_base * (1.0 - h_factor) + c_hazard_amber[0] * h_factor
                    g_base = g_base * (1.0 - h_factor) + c_hazard_amber[1] * h_factor
                    b_base = b_base * (1.0 - h_factor) + c_hazard_amber[2] * h_factor

            # Modulate with multi-octave surface grime / soot
            grime_mul = 0.82 + 0.36 * (patina + 0.5)
            r = int(max(0, min(255, round(r_base * grime_mul))))
            g = int(max(0, min(255, round(g_base * grime_mul))))
            b = int(max(0, min(255, round(b_base * grime_mul))))

            pixels.append((r, g, b))

    img.putdata(pixels)
    img.save(output_path)
    print(f"[SUCCESS] Generated weathered rib texture: {output_path} ({width}x{height})")

if __name__ == "__main__":
    generate_rib_texture()
