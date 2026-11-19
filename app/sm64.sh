#!/bin/sh
# Super Mario 64 (HarbourMasters' Ghostship) with the GLES2 renderer, for FakeR36S-OS: its first start makes the
# game's assets (sm64.o2r) from the player's ROM (common.sh). Saves, settings, save states and assets in
# HOME/.config/sm64 (overrides: its env); log: HOME/logs/sm64.log. https://github.com/Eeman1113/FakeR36S-SM64
PORT=sm64 ELF=Ghostship TITLE="Super Mario 64" O2R=sm64.o2r CONFIG=ghostship.cfg.json
TAKES="the N64 USA or Japan version"
. ./common.sh
start
