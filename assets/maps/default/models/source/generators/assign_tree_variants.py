#!/usr/bin/env python3
"""
Assign tree_variant values to tree objects in object_map.json.
Distributes 6 tree types across 90 trees based on terrain/location:
  0 = Oak (most common, grasslands)
  1 = Pine (higher elevations, northern areas)
  2 = Birch (moderate elevations, scattered)
  3 = Willow (near water, lower elevations)
  4 = Cherry Blossom (villages, settlements)
  5 = Dead Tree (rocky terrain, sparse)
"""
import os
import json
import math
import random

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MAP_DIR = os.path.dirname(os.path.dirname(os.path.dirname(SCRIPT_DIR)))
INPUT_PATH = os.path.join(MAP_DIR, "object_map.json")
OUTPUT_PATH = INPUT_PATH

def assign_tree_variants():
    with open(INPUT_PATH, 'r') as f:
        data = json.load(f)

    random.seed(42)  # Deterministic for reproducibility

    # Settlement centers for cherry blossom proximity check
    settlements = data.get("settlements", [])
    settlement_coords = []
    for s in settlements:
        theta_s = s.get("u", 0.5) * 2 * math.pi - math.pi
        z_s = (s.get("v", 0.5) - 0.5) * 18000.0
        settlement_coords.append((theta_s, z_s))

    tree_count = 0
    variant_counts = [0] * 6

    for obj in data.get("objects", []):
        if obj.get("object_type") != 6:  # Not a tree
            continue

        tree_count += 1
        theta = obj.get("theta", 0.0)
        z = obj.get("z", 0.0)
        elev = obj.get("elevation", 30.0)
        v = obj.get("v", 0.5)

        # Check proximity to settlements
        near_settlement = False
        for st, sz in settlement_coords:
            dtheta = abs(theta - st)
            if dtheta > math.pi:
                dtheta = 2 * math.pi - dtheta
            dist = math.sqrt((dtheta * 4000) ** 2 + (z - sz) ** 2)
            if dist < 600:
                near_settlement = True
                break

        # Check if near water (lower elevation)
        near_water = elev < 32.0

        # Check if high elevation
        high_elev = elev > 50.0

        # Determine variant based on environmental factors + forced variety
        # Every 15th tree is a cherry blossom, every 13th is a willow
        if tree_count % 15 == 0:
            variant = 4  # Cherry Blossom (forced variety)
        elif tree_count % 13 == 0:
            variant = 3  # Willow (forced variety)
        elif near_settlement and random.random() < 0.55:
            variant = 4  # Cherry Blossom near settlements
        elif near_water and random.random() < 0.55:
            variant = 3  # Willow near water
        elif high_elev and random.random() < 0.55:
            variant = 1  # Pine at high elevations
        elif random.random() < 0.08:
            variant = 5  # Dead tree (rare, anywhere)
        else:
            # Distribute remaining among oak, pine, birch
            roll = random.random()
            if roll < 0.50:
                variant = 0  # Oak (most common)
            elif roll < 0.75:
                variant = 1  # Pine
            else:
                variant = 2  # Birch

        obj["tree_variant"] = variant
        obj["tree_variant_name"] = ["OAK", "PINE", "BIRCH", "WILLOW", "CHERRY_BLOSSOM", "DEAD_TREE"][variant]
        variant_counts[variant] += 1

    # Update statistics
    if "statistics" in data:
        data["statistics"]["tree_variants"] = {
            "oak": variant_counts[0],
            "pine": variant_counts[1],
            "birch": variant_counts[2],
            "willow": variant_counts[3],
            "cherry_blossom": variant_counts[4],
            "dead_tree": variant_counts[5]
        }

    with open(OUTPUT_PATH, 'w') as f:
        json.dump(data, f, indent=2)

    print(f"Assigned variants to {tree_count} trees:")
    names = ["Oak", "Pine", "Birch", "Willow", "Cherry Blossom", "Dead Tree"]
    for i, name in enumerate(names):
        print(f"  {name}: {variant_counts[i]}")

if __name__ == "__main__":
    assign_tree_variants()
