"""Run an asyncio event loop on a background thread.

AppKit owns the main thread's run loop, but Bleak needs an asyncio loop.
We run one persistent loop on a daemon thread and marshal coroutines onto
it from AppKit menu callbacks via :meth:`AsyncRunner.submit`.
"""

from __future__ import annotations

import asyncio
import concurrent.futures
import threading
from typing import Any, Awaitable, Callable, Optional


class AsyncRunner:
    def __init__(self) -> None:
        self._loop = asyncio.new_event_loop()
        self._ready = threading.Event()
        self._thread = threading.Thread(
            target=self._run, name="melk-asyncio", daemon=True
        )
        self._thread.start()
        self._ready.wait(5.0)

    def _run(self) -> None:
        asyncio.set_event_loop(self._loop)
        self._loop.call_soon(self._ready.set)
        self._loop.run_forever()

    def submit(
        self,
        coro: Awaitable[Any],
        done: Optional[Callable[[concurrent.futures.Future], None]] = None,
    ) -> concurrent.futures.Future:
        """Schedule a coroutine on the loop; optional done callback."""
        fut = asyncio.run_coroutine_threadsafe(coro, self._loop)
        if done is not None:
            fut.add_done_callback(done)
        return fut

    def stop(self) -> None:
        self._loop.call_soon_threadsafe(self._loop.stop)
