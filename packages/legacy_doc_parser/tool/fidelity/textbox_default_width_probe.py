#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Paired true-absent/explicit width controls, preserving source coordinates."""
import json

import textbox_paint_probe as probe

CASES = {
    "implicit-plain": "",
    "explicit-threequarter": "",
    "implicit-dashed": '<v:stroke dashstyle="shortdash"/>',
    "implicit-disabled": '<v:stroke on="f"/>',
}

_authored = probe.authored


def authored(paint):
    document = _authored(paint).replace('strokeweight="2pt"', 'strokeweight="0.75pt"')
    if paint == CASES["implicit-disabled"]:
        document = document.replace('<v:stroke on="f"/>', '').replace(
            'strokeweight="0.75pt"', 'stroked="f" strokeweight="0.75pt"')
    return document


def prepare_binary(args, name, binary, directory):
    if not name.startswith("implicit-"):
        return binary, {"applied": False}
    definitions = directory / "source-properties.json"
    # A real absent source operand; this does not insert a zero/default value.
    # The helper rejects removal if the value would remain inherited from Dgg.
    properties = {"1cb": None}
    if name == "implicit-disabled":
        # Prove an explicit used false in source, independently of whether the
        # native OOXML exporter preserves a nested v:stroke on="f" flag.
        properties["1ff"] = 0x00080000
    probe.write(definitions, properties)
    controlled = directory / "binary/controlled.doc"
    argv = [args.dart, "run", probe.ROOT / "tool/fidelity/textbox_property_control.dart",
            binary, controlled, definitions]
    receipt = json.loads(probe.command(argv, cwd=probe.ROOT))
    receipt.update(applied=True, inputSha256=probe.digest(binary),
                   outputSha256=probe.digest(controlled),
                   propertiesSha256=probe.digest(definitions),
                   command=[str(value) for value in argv])
    probe.write(directory / "source-control.json", receipt)
    return controlled, receipt


if __name__ == "__main__":
    if not __debug__:
        raise SystemExit("Measurements require normal Python without -O.")
    probe.CASES = CASES
    probe.authored = authored
    probe.PREPARE_BINARY = prepare_binary
    probe.main()
