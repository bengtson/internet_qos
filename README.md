# InternetQOS

Monitors home internet access by looking at the signal page of the Motorola
modem web page. Data is captured at the top of each minute and pushed every 10
seconds to the Tack Status application. Yes, 1 minute and 10 seconds makes no
sense.

## Expected Signal Levels

Generally in best operating mode, there will be 8 channels down and 3 up. I've always seen 8 down but sometimes only 1 or 2 up.

Down levels should be -7 dBmV to +7 dBmV with a target of 0 dBmV.
Up levels should be 50 dBmV or as close as possible. Mid 40's is what I'm seeing here.

## To Do List

Need to revise how samples are stored to a file. Preferably, these would
be in a readable but also scannable format.

## Installation

  cd /home/pi
  git clone 
