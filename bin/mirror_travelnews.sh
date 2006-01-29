#!/bin/bash

cd /home/system/colloquy/botbot/data && \
	wget -q -m -np -nH \
		-A dtd,ent,xml \
		http://cps0.mh.bbc.co.uk/travelnews/en/

