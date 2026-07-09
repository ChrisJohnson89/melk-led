"""melk_led: native local control of MELK-OA10 BLE LED controllers."""

from __future__ import annotations

import logging

from . import protocol
from .config import Config, load as load_config
from .device import MelkDevice, MelkError, scan
from .manager import MelkManager
from .protocol import Effect

__version__ = "0.1.0"

__all__ = [
    "protocol",
    "Effect",
    "MelkDevice",
    "MelkManager",
    "MelkError",
    "Config",
    "load_config",
    "scan",
    "setup_logging",
    "__version__",
]


def setup_logging(level: int = logging.INFO) -> None:
    """Configure a sensible default log format for CLI / API use."""
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )
