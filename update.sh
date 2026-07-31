#!/bin/bash

# in order to update the script to the last version without losing your configuration,
# first go in evernode_monitor folder:
#
# cd evernode_monitor
#
# and then give execute permission to the script:
#
# chmod +x update.sh
#
# now you can execute the script:
#
# sudo ./update.sh


echo  "move to parent folder"
cd ..

echo "backup .env file"
cp evernode_monitor/.env .env

echo "remove evernode_monitor folder"
rm evernode_monitor -r -f

echo "clone the github repo"
git clone https://github.com/genesis-one-seven/evernode_monitor/

echo "restore .env file"
cp  .env evernode_monitor/.env

echo "delete backup .env file"
rm  .env

echo "go back to script folder"
cd evernode_monitor

echo "install dependencies"
npm install