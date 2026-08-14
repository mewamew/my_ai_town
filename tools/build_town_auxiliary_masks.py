#!/usr/bin/env python3
"""Build lossless runtime masks used by the town environment and movement.

Channel contract:
  R = directional shadow caster mask R
  G = puddle mask R
  B = window ground-projection mask G
  A = precomputed window emissive/glow class

The source masks remain the authoring truth. This tool refuses inputs whose
channel shape no longer matches the contract and verifies every written byte.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import struct
import sys

try:
    import numpy as np
    from PIL import Image
except ImportError as error:
    raise SystemExit(
        "build_town_auxiliary_masks.py requires Pillow and NumPy"
    ) from error


DEFAULT_ASSET_DIR = Path("game/world/presentation/environment/assets")
DEFAULT_TOWN_MAP = Path("game/world/maps/town/assets/town.png")


def _load_rgba(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        if image.mode != "RGBA":
            raise ValueError(f"{path} must stay RGBA, got {image.mode}")
        return np.asarray(image, dtype=np.uint8).copy()


def _require_binary_rgb_mask(name: str, pixels: np.ndarray) -> None:
    if not (
        np.array_equal(pixels[:, :, 0], pixels[:, :, 1])
        and np.array_equal(pixels[:, :, 0], pixels[:, :, 2])
    ):
        raise ValueError(f"{name} RGB channels are no longer identical")
    if not np.all(pixels[:, :, 3] == 255):
        raise ValueError(f"{name} alpha is no longer fully opaque")
    values = np.unique(pixels[:, :, 0])
    if not np.all(np.isin(values, np.array([0, 255], dtype=np.uint8))):
        raise ValueError(f"{name} is no longer a binary mask: {values.tolist()}")


def _require_window_mask_contract(pixels: np.ndarray) -> None:
    if not np.all(pixels[:, :, 2] == 0):
        raise ValueError("window mask blue channel is no longer empty")
    if not np.all(pixels[:, :, 3] == 255):
        raise ValueError("window mask alpha is no longer fully opaque")
    emissive_values = np.unique(pixels[:, :, 0])
    if not np.all(
        np.isin(emissive_values, np.array([0, 255], dtype=np.uint8))
    ):
        raise ValueError(
            "window emissive channel is no longer binary: "
            f"{emissive_values.tolist()}"
        )


def _channel_hash(channel: np.ndarray) -> str:
    return hashlib.sha256(channel.tobytes(order="C")).hexdigest()


def _dilate_binary_mask(source: np.ndarray, radius: int, step: int) -> np.ndarray:
    height, width = source.shape
    padding = radius * step
    padded = np.pad(
        source,
        ((padding, padding), (padding, padding)),
        mode="edge",
    )
    dilated = np.zeros_like(source, dtype=bool)
    for offset_y in range(-radius, radius + 1):
        for offset_x in range(-radius, radius + 1):
            start_y = padding + offset_y * step
            start_x = padding + offset_x * step
            dilated |= padded[
                start_y : start_y + height,
                start_x : start_x + width,
            ]
    return dilated


def _window_glow_classes(window: np.ndarray) -> np.ndarray:
    source = window[:, :, 0] != 0
    # Exact offline equivalent of the former shader's 25 near samples at
    # three-pixel spacing and 49 far samples at six-pixel spacing.
    near = _dilate_binary_mask(source, radius=2, step=3)
    far = _dilate_binary_mask(source, radius=3, step=6)
    return np.where(
        source,
        255,
        np.where(near, 170, np.where(far, 85, 0)),
    ).astype(np.uint8)


def _write_verified_png(pixels: np.ndarray, mode: str, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    Image.fromarray(pixels, mode=mode).save(
        temporary,
        format="PNG",
        compress_level=9,
        optimize=False,
    )
    with Image.open(temporary) as written_image:
        if written_image.mode != mode:
            temporary.unlink(missing_ok=True)
            raise ValueError(f"written {output.name} mode differs")
        written = np.asarray(written_image, dtype=np.uint8).copy()
    if not np.array_equal(written, pixels):
        temporary.unlink(missing_ok=True)
        raise ValueError(f"written {output.name} differs from source pixels")
    os.replace(temporary, output)


def _build_walkability_mask(
    surface: np.ndarray,
    town: np.ndarray,
) -> np.ndarray:
    if surface.shape != town.shape:
        raise ValueError(
            "surface mask and town map must have identical dimensions: "
            f"surface={surface.shape}, town={town.shape}"
        )
    surface_water = surface[:, :, 0] > 2
    explicit_ground = surface[:, :, 1] > 2
    town_rgb = town[:, :, :3].astype(np.float64) / 255.0
    red = town_rgb[:, :, 0]
    green = town_rgb[:, :, 1]
    blue = town_rgb[:, :, 2]
    blue_bias = blue - np.maximum(red, green * 0.82)
    cyan_bias = np.minimum(green, blue) - red * 1.12
    brightness = np.maximum(red, np.maximum(green, blue))
    looks_like_water = (
        (blue_bias > 0.035)
        & (cyan_bias > 0.02)
        & (brightness > 0.40)
    )
    dry = (~surface_water) & (explicit_ground | (~looks_like_water))
    return np.where(dry, 255, 0).astype(np.uint8)


def _write_verified_walkability(
    walkability: np.ndarray,
    output: Path,
) -> bytes:
    height, width = walkability.shape
    dry = walkability.reshape(-1) != 0
    packed = np.packbits(dry, bitorder="little").tobytes()
    header = struct.pack("<4sIII", b"ATWM", 1, width, height)
    payload = header + packed
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    temporary.write_bytes(payload)
    written = temporary.read_bytes()
    if written != payload:
        temporary.unlink(missing_ok=True)
        raise ValueError(f"written {output.name} differs from source bits")
    magic, version, written_width, written_height = struct.unpack(
        "<4sIII", written[:16]
    )
    if (
        magic != b"ATWM"
        or version != 1
        or written_width != width
        or written_height != height
        or len(written[16:]) != (width * height + 7) // 8
    ):
        temporary.unlink(missing_ok=True)
        raise ValueError(f"written {output.name} has an invalid header or size")
    os.replace(temporary, output)
    return packed


def build(
    asset_dir: Path,
    town_map_path: Path,
    auxiliary_output: Path,
    walkability_output: Path,
) -> None:
    shadow = _load_rgba(asset_dir / "town_shadow_caster_mask.png")
    puddle = _load_rgba(asset_dir / "town_puddle_mask.png")
    window = _load_rgba(asset_dir / "town_window_emissive_mask.png")
    surface = _load_rgba(asset_dir / "town_surface_masks.png")
    town = _load_rgba(town_map_path)
    if shadow.shape != puddle.shape or shadow.shape != window.shape:
        raise ValueError(
            "town auxiliary masks must have identical dimensions: "
            f"shadow={shadow.shape}, puddle={puddle.shape}, window={window.shape}"
        )
    _require_binary_rgb_mask("shadow mask", shadow)
    _require_binary_rgb_mask("puddle mask", puddle)
    _require_window_mask_contract(window)

    packed = np.empty_like(shadow)
    packed[:, :, 0] = shadow[:, :, 0]
    packed[:, :, 1] = puddle[:, :, 0]
    packed[:, :, 2] = window[:, :, 1]
    packed[:, :, 3] = _window_glow_classes(window)

    _write_verified_png(packed, "RGBA", auxiliary_output)
    walkability = _build_walkability_mask(surface, town)
    walkability_bits = _write_verified_walkability(
        walkability,
        walkability_output,
    )
    print(
        "TOWN_RUNTIME_MASK_BUILD_PASS "
        f"size={packed.shape[1]}x{packed.shape[0]} "
        f"shadow={_channel_hash(packed[:, :, 0])} "
        f"puddle={_channel_hash(packed[:, :, 1])} "
        f"window_beam={_channel_hash(packed[:, :, 2])} "
        f"window_glow={_channel_hash(packed[:, :, 3])} "
        f"walkability={hashlib.sha256(walkability_bits).hexdigest()} "
        f"dry_pixels={int(np.count_nonzero(walkability))} "
        f"packed_bytes={len(walkability_bits)}"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset-dir", type=Path, default=DEFAULT_ASSET_DIR)
    parser.add_argument(
        "--auxiliary-output",
        type=Path,
        default=DEFAULT_ASSET_DIR / "town_auxiliary_masks.png",
    )
    parser.add_argument("--town-map", type=Path, default=DEFAULT_TOWN_MAP)
    parser.add_argument(
        "--walkability-output",
        type=Path,
        default=DEFAULT_ASSET_DIR / "town_dry_walkability_mask.bin",
    )
    args = parser.parse_args()
    try:
        build(
            args.asset_dir,
            args.town_map,
            args.auxiliary_output,
            args.walkability_output,
        )
    except (OSError, ValueError) as error:
        print(f"TOWN_AUXILIARY_MASK_BUILD_FAILED {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
