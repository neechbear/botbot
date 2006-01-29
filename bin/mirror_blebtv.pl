#!/usr/bin/perl -w

use strict;
use LWP::Simple;

mkdir('/home/system/colloquy/botbot/data/blebtv');
chdir('/home/system/colloquy/botbot/data/blebtv');

my @channels = qw(bbc1 bbc2 itv1 ch4 five abc1 bbc1_n_ireland bbc1_scotland
				bbc1_wales bbc2_n_ireland bbc2_scotland bbc2_wales bbc3 bbc4
				bbc7 bbc_6music bbc_news24 bbc_parliament bbc_radio1
				bbc_radio1_xtra bbc_radio2 bbc_radio3 bbc_radio4
				bbc_radio5_live bbc_radio5_live_sports_extra
				bbc_radio_scotland bbc_world_service boomerang bravo
				british_eurosport cartoon_network cbbc cbeebies challenge
				discovery discovery_kids discovery_real_time disney e4
				film_four ftn itv2 itv3 itv4 living_tv men_and_motors more4
				mtv nick_junior nickelodeon oneword paramount paramount2 s4c
				scifi sky_cinema1 sky_cinema2 sky_movies1 sky_movies2
				sky_movies3 sky_movies4 sky_movies5 sky_movies6 sky_movies7
				sky_movies8 sky_movies9 sky_movies_cinema sky_movies_cinema2
				sky_one sky_one_mix sky_sports1 sky_sports2 sky_sports3
				sky_sports_news sky_sports_xtra sky_three sky_travel tcm
				uk_bright_ideas uk_drama uk_gold uk_history uk_style
				uktv_documentary uktv_people vh1);

my $url = 'http://www.bleb.org/tv/data/listings?days=0..6&format=XMLTV&channels=';

$url .= join(',',@channels);

mirror($url, 'blebtv.zip');
system('unzip -q -o blebtv.zip');

