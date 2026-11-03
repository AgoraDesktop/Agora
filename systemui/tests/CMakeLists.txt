# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

# **THE ABOUT PANEL'S LINES ARE MACHINE FACTS, AND A SUITE CAN READ THEM WITHOUT A SESSION.** `--dump-about` prints
# exactly what the panel draws, so the assertion is that the panel has something true to say on THIS machine: a title
# with the desktop's own version in it, and at least the operating system under it. A machine whose /proc is missing
# still answers the title, which is why the first line is the one that is required.
add_test(NAME systemui-about-lines
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/check_about.sh" "$<TARGET_FILE:SystemUI>")
