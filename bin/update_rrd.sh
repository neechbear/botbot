#!/bin/bash

umask 0002
cd /home/system/colloquy/botbot && \
	(zcat logs/botbot.log.1.gz;cat logs/botbot.log) | ./rrd.pl

