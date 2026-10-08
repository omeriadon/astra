#!/usr/bin/env python3
"""Regression checks for process identity and aggregate memory attribution."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Process:
    pid: int
    start: int | None
    bytes: int | None

    @property
    def identity(self):
        return self.pid, self.start


def aggregate(snapshots):
    processes = {}
    for snapshot in snapshots:
        for process in snapshot:
            if process.bytes is not None:
                processes[process.identity] = process.bytes
    return len(processes), sum(processes.values()) if processes else None


def main():
    shared = Process(42, 100, 300)
    replacement = Process(42, 200, 700)
    unavailable = Process(43, 100, None)

    assert aggregate([[shared], [shared]]) == (1, 300)
    assert aggregate([[shared], [replacement]]) == (2, 1000)
    assert aggregate([[unavailable]]) == (0, None)
    assert aggregate([[shared, unavailable], [shared]]) == (1, 300)


if __name__ == "__main__":
    main()
