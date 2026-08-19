#!/usr/bin/env python3

from __future__ import annotations

import unittest

from run_im400_full import Runner


class FakeDevice:
    def __init__(self, hierarchy: str) -> None:
        self.hierarchy = hierarchy
        self.clicked: tuple[int, int] | None = None

    def dump_hierarchy(self) -> str:
        return self.hierarchy

    def window_size(self) -> tuple[int, int]:
        return (1200, 2640)

    def click(self, x: int, y: int) -> None:
        self.clicked = (x, y)


class BottomNavigationTest(unittest.TestCase):
    def make_runner(self, hierarchy: str) -> Runner:
        runner = Runner.__new__(Runner)
        runner.package = "com.genericim.ma100"
        runner.device = FakeDevice(hierarchy)
        return runner

    def test_badged_bottom_tab_ignores_matching_chat_content(self) -> None:
        runner = self.make_runner(
            """
            <hierarchy>
              <node package="com.genericim.ma100" clickable="true"
                    content-desc="消息详情" bounds="[0,200][1200,500]" />
              <node package="com.genericim.ma100" clickable="true"
                    content-desc="4&#10;消息" bounds="[116,2408][358,2486]" />
            </hierarchy>
            """
        )

        self.assertTrue(runner.click_bottom_desc("消息"))
        self.assertEqual((237, 2447), runner.device.clicked)

    def test_returns_false_without_bottom_match(self) -> None:
        runner = self.make_runner(
            """
            <hierarchy>
              <node package="com.genericim.ma100" clickable="true"
                    content-desc="消息详情" bounds="[0,200][1200,500]" />
            </hierarchy>
            """
        )

        self.assertFalse(runner.click_bottom_desc("消息"))
        self.assertIsNone(runner.device.clicked)


if __name__ == "__main__":
    unittest.main()
