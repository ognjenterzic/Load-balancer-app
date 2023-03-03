#!/bin/bash
sudo apt --version
OPT=`echo $?`
if [ $OPT == 0 ]
then
sudo apt update -y
sudo apt install apache2 wget unzip -y
wget https://www.tooplate.com/zip-templates/2130_waso_strategy.zip
unzip 2130_waso_strategy.zip
sudo mkdir /var/www/html/waso/
sudo cp -r 2130_waso_strategy/* /var/www/html/waso/
sudo systemctl restart apache2
else
sudo yum update -y
sudo yum install httpd wget unzip -y
wget https://www.tooplate.com/zip-templates/2129_crispy_kitchen.zip
unzip 2129_crispy_kitchen.zip
sudo mkdir /var/www/html/crispy/
sudo cp -r 2129_crispy_kitchen/* /var/www/html/crispy/
sudo systemctl restart httpd
fi