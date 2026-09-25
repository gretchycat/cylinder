#!/usr/bin/env python3
"""
generate_end_cap_rib_texture.py
--------------------------------
Generates a circular 1024x1024 radial rib texture for the O'Neill cylinder
hemispherical end cap bulkheads.

Features:
- 32 primary structural radial rib beams radiating from center to perimeter.
- 8 heavy master keel ribs (every 45 degrees) with amber hazard warning stripes.
- 8 concentric structural compression rings (hoop girders) with reinforced gussets.
- Central Zero-G spaceport docking collar with golden guidance and cyan beacon rings.
- Double rows of circular aerospace rivets along all radial rib flanges.
- Fluted / corrugated alloy pressure-hull paneling in bays between radial ribs.
- Weathered industrial patina: dark charcoal alloy, exposed bare metal edge scuffs,
  and ambient occlusion shadow crevices.
"""

import math
import random
from PIL import Image

def generate_radial_rib_texture(
    width: int = 1024,
    height: int = 1024,
    output_path: str = "assets/textures/terrain/end_cap_ribs.png",
    seed: int = 42
):
    rng = random.Random(seed)
    img = Image.new("RGB", (width, height))

    cx = width * 0.5
    cy = height * 0.5
    max_r = width * 0.49

    # Palette
    c_panel_dark    = (36, 40, 46)      # Recessed bay paneling
    c_panel_mid     = (52, 56, 64)      # Base bulkhead alloy
    c_rib_face      = (78, 85, 96)      # Raised rib face
    c_scuff_alloy   = (180, 190, 205)   # Bare metal highlights along rib edges
    c_crevice       = (18, 20, 24)      # Recessed shadow crevice
    c_rivet         = (150, 160, 175)   # Rivet heads
    c_amber_hazard  = (210, 155, 35)    # Industrial amber hazard stripe
    c_gold_ring     = (225, 185, 45)    # Spaceport golden guidance ring
    c_cyan_beacon   = (45, 195, 220)    # Spaceport cyan docking beacon ring

    num_spokes = 32
    d_spoke_angle = math.tau / float(num_spokes)

    # Concentric ring radii in pixels
    ring_radii = [60.0, 115.0, 175.0, 235.0, 295.0, 355.0, 415.0, 470.0]
    ring_thickness = 8.0

    pixels = []

    for y in range(height):
        dy = float(y) - cy
        for x in range(width):
            dx = float(x) - cx
            dist = math.sqrt(dx * dx + dy * dy)
            angle = math.atan2(dy, dx)
            if angle < 0.0:
                angle += math.tau

            # Outside outer rim
            if dist > max_r + 4.0:
                pixels.append((22, 24, 28))
                continue

            # Normalized radius 0.0 at center, 1.0 at rim
            r_norm = min(1.0, dist / max_r)

            # 1. Central Zero-G Spaceport Docking Collar (dist <= 55 px)
            if dist <= 55.0:
                if dist < 12.0:
                    # Central airlock / vacuum transit tunnel
                    pixels.append((15, 16, 18))
                elif abs(dist - 22.0) <= 3.5:
                    # Cyan active docking beacon ring
                    pixels.append(c_cyan_beacon)
                elif abs(dist - 38.0) <= 4.0:
                    # Golden guidance collar ring
                    pixels.append(c_gold_ring)
                elif abs(dist - 52.0) <= 2.5:
                    # Outer docking collar flange
                    pixels.append(c_scuff_alloy)
                else:
                    # Docking plaza metal floor
                    val = 65 + int(10 * math.sin(angle * 8.0))
                    pixels.append((val, val + 5, val + 12))
                continue

            # 2. Radial Rib Spokes (32 radial spokes radiating outward)
            spoke_idx = int(round(angle / d_spoke_angle)) % num_spokes
            center_spoke_angle = spoke_idx * d_spoke_angle
            angle_diff = abs(angle - center_spoke_angle)
            if angle_diff > math.pi:
                angle_diff = math.tau - angle_diff

            # Arc distance in pixels from the nearest radial spoke centerline
            arc_dist_px = angle_diff * dist

            # Master keel ribs (every 4th spoke = 8 major keels) are wider
            is_master_keel = (spoke_idx % 4 == 0)
            rib_half_w = 9.0 if is_master_keel else 6.0

            is_on_rib = arc_dist_px <= rib_half_w
            is_rib_edge = abs(arc_dist_px - rib_half_w) <= 1.8
            is_rib_crevice = abs(arc_dist_px - (rib_half_w + 3.0)) <= 2.0

            # 3. Concentric Structural Compression Rings (Hoop Girders)
            is_on_ring = False
            is_ring_edge = False
            for rr in ring_radii:
                dr = abs(dist - rr)
                if dr <= ring_thickness * 0.5:
                    is_on_ring = True
                if abs(dr - ring_thickness * 0.5) <= 1.5:
                    is_ring_edge = True

            # 4. Rivet Lines along radial rib flanges
            is_rivet = False
            is_rivet_rim = False
            if dist > 65.0:
                rivet_spacing = 18.0 # Rivet every 18 pixels radially
                dr_riv = abs((dist % rivet_spacing) - rivet_spacing * 0.5)
                # Flange offset from spoke centerline
                flange_dist = rib_half_w * 0.65
                d_arc_riv = abs(arc_dist_px - flange_dist)
                d_rivet_total = math.sqrt(d_arc_riv * d_arc_riv + dr_riv * dr_riv)
                if d_rivet_total <= 2.2:
                    is_rivet = True
                elif d_rivet_total <= 3.4:
                    is_rivet_rim = True

            # 5. Corrugation / Fluting in bays between radial ribs
            corrugation = 0.0
            if not is_on_rib and not is_on_ring:
                # Radial fluting: waves along angle
                flute_freq = 6.0
                rel_angle = arc_dist_px / (dist * d_spoke_angle * 0.5)
                corrugation = math.sin(rel_angle * math.pi * flute_freq) * 0.5 + 0.5

            # 6. Assemble Color
            if is_on_rib:
                # Radial rib top face
                r_col = c_rib_face[0]
                g_col = c_rib_face[1]
                b_col = c_rib_face[2]

                # Master keel ribs have amber hazard warning chevrons
                if is_master_keel and (int(dist / 32.0) % 2 == 1):
                    r_col = c_amber_hazard[0]
                    g_col = c_amber_hazard[1]
                    b_col = c_amber_hazard[2]

                # Raised edge highlight (worn bare alloy)
                if is_rib_edge:
                    r_col = c_scuff_alloy[0]
                    g_col = c_scuff_alloy[1]
                    b_col = c_scuff_alloy[2]

                # Intersection gusset reinforcement (where radial rib meets concentric ring)
                if is_on_ring:
                    r_col = min(255, int(r_col * 1.15))
                    g_col = min(255, int(g_col * 1.15))
                    b_col = min(255, int(b_col * 1.18))
            elif is_on_ring:
                # Concentric ring beam
                r_col = c_panel_mid[0] + 15
                g_col = c_panel_mid[1] + 15
                b_col = c_panel_mid[2] + 18
                if is_ring_edge:
                    r_col = c_scuff_alloy[0] * 0.85
                    g_col = c_scuff_alloy[1] * 0.85
                    b_col = c_scuff_alloy[2] * 0.85
            else:
                # Recessed bay paneling with fluted corrugation
                c_mult = 0.85 + 0.30 * corrugation
                r_col = c_panel_dark[0] * c_mult
                g_col = c_panel_dark[1] * c_mult
                b_col = c_panel_dark[2] * c_mult

                # Shadow crevice adjacent to rib wall
                if is_rib_crevice:
                    r_col = c_crevice[0]
                    g_col = c_crevice[1]
                    b_col = c_crevice[2]

            # Rivet overlay
            if is_rivet:
                r_col = c_rivet[0]
                g_col = c_rivet[1]
                b_col = c_rivet[2]
            elif is_rivet_rim:
                r_col = c_crevice[0]
                g_col = c_crevice[1]
                b_col = c_crevice[2]

            # Outer perimeter mounting rim (dist >= 475 px)
            if dist >= 475.0:
                rim_factor = (dist - 475.0) / 25.0
                r_col = r_col * (1.0 - rim_factor) + c_panel_mid[0] * rim_factor
                g_col = g_col * (1.0 - rim_factor) + c_panel_mid[1] * rim_factor
                b_col = b_col * (1.0 - rim_factor) + c_panel_mid[2] * rim_factor

            # Subtle organic metal noise variation
            noise = (math.sin(x * 0.3) * math.cos(y * 0.3)) * 6.0
            r = int(max(0, min(255, round(r_col + noise))))
            g = int(max(0, min(255, round(g_col + noise))))
            b = int(max(0, min(255, round(b_col + noise))))

            pixels.append((r, g, b))

    img.putdata(pixels)
    img.save(output_path)
    print(f"[SUCCESS] Generated circular radial rib texture: {output_path} ({width}x{height})")

if __name__ == "__main__":
    generate_radial_rib_texture()
