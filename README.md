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
  git clone https://github.com/bengtson/internet_qos.git
  cd /home/pi/internet_qos
  mix deps.get
  iex -S mix    # to test.
  
  
## Updating software

  sudo systemctl stop tack-internet-qos.service
  cd /home/pi
  sudo rm -rf internet_qos
  git clone https://github.com/bengtson/internet_qos.git
  cd /home/pi/internet_qos
  mix deps.get
  sudo systemctl start tack-internet-qos.service
  
  
## Setting up 'systemd'

Move the provided service file to the systemd service directory.

    cd /home/pi/tack_status
    sudo cp tack-internet-qos.service /etc/systemd/system
    sudo systemctl enable tack-internet-qos.service
    sudo systemctl start tack-internet-qos.service
    
If this is the first execution of a new version, it will take a minute or two to compile all the code. You can check on the state of the compile with:

    sudo systemctl status tack-internet-qos.service
    
The server should now be running. Test that it restarts when the system is rebooted or the power is sequenced. A reboot takes about 30 seconds.

    sudo reboot
    
Note : The following command shows the log for the specified service.

    journalctl --unit=tack-internet-qos.service | tail -n 30

  
  
  
