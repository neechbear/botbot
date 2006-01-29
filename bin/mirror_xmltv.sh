#!/bin/bash

cd /home/system/colloquy/botbot/data && \
	wget -q -m -np -nH \
		http://xmltv.radiotimes.com/xmltv/channels.dat \
		http://xmltv.radiotimes.com/xmltv/45.dat 

