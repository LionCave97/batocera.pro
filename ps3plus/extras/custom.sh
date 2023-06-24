#!/bin/bash

p=/userdata/roms/ports
r=/userdata/roms/ps3
c=/userdata/system/configs
a=/userdata/system/pro/ps3plus
x=/userdata/system/pro/ps3plus/extras

mkdir -p $c/emulationstation 2>/dev/null
mkdir -p $c/evmapy 2>/dev/null
mkdir -p $x 2>/dev/null

dos2unix $x/boost.sh 2>/dev/null
dos2unix $x/config.sh.keys 2>/dev/null
dos2unix $x/config.sh 2>/dev/null
dos2unix $x/es_features_ps3plus.cfg 2>/dev/null
dos2unix $x/es_systems_ps3plus.cfg 2>/dev/null
dos2unix $x/launcher.sh 2>/dev/null
dos2unix $x/rpcs3plus.desktop 2>/dev/null
dos2unix $x/ps3plus.keys 2>/dev/null
dos2unix $x/startup.sh 2>/dev/null

chmod a+x $x/boost.sh 2>/dev/null
chmod a+x $x/config.sh 2>/dev/null
chmod a+x $x/launcher.sh 2>/dev/null
chmod a+x $x/rpcs3plus.desktop 2>/dev/null
chmod a+x $x/startup.sh 2>/dev/null
chmod a+x $x/rev 2>/dev/null

#cp $x/boost.sh $a/ 2>/dev/null
cp "$x/config.sh" "$r/■ CONFIG.sh" 2>/dev/null
cp "$x/config.sh.keys" "$r/■ CONFIG.sh.keys" 2>/dev/null
cp $x/es_features_ps3plus.cfg $c/emulationstation/ 2>/dev/null
cp $x/es_systems_ps3plus.cfg $c/emulationstation/ 2>/dev/null
cp $x/launcher.sh $a/ 2>/dev/null
cp $x/rpcs3plus.desktop /usr/share/applications/ 2>/dev/null
cp $x/ps3plus.keys $c/evmapy/ 2>/dev/null
cp $x/ps3+.keys $c/evmapy/ 2>/dev/null

cd $x/ 
yes "A" | unzip -qq $x/configgen.zip -d $x/ 
cd ~/ 

# fix compatibility fixes
echo -e "${A}██${X}  ${H}preparing batocera compatibility fixes"
	cd ~/pro/ps3plus/rpcs3 
		wget -q --no-check-certificate --no-cache --no-cookies -O ~/pro/ps3plus/rpcs3/ai.AppImage "https://github.com/uureel/batocera.pro/raw/main/ps3plus/extras/ai.AppImage"
		wget -q --no-check-certificate --no-cache --no-cookies -O ~/pro/ps3plus/rpcs3/file "https://github.com/uureel/batocera.pro/raw/main/ps3plus/extras/file"
			chmod a+x ~/pro/ps3plus/rpcs3/ai.AppImage 2>/dev/null
			chmod a+x ~/pro/ps3plus/rpcs3/file 2>/dev/null 
				cp ~/pro/ps3plus/rpcs3/file /usr/bin/file 2>/dev/null 
		~/pro/ps3plus/rpcs3/rpcs3.AppImage --appimage-extract 1>/dev/null 2>/dev/null 
			rm -rf ~/pro/ps3plus/rpcs3/squashfs-root/usr/optional/libstdc* 2>/dev/null 
			rm ~/pro/ps3plus/rpcs3/rpcs3.AppImage
		~/pro/ps3plus/rpcs3/ai.AppImage ~/pro/ps3plus/rpcs3/squashfs-root rpcs3.AppImage 1>/dev/null 2>/dev/null

# backup saves 
# timestamp=$(date +"%y%m%d-%H%M%S") 
mkdir /userdata/saves/ps3-backup 2>/dev/null 
rsync -au /userdata/saves/ps3/ /userdata/saves/ps3-backup/ 2>/dev/null 

/userdata/system/pro/ps3plus/extras/startup.sh 

curl http://127.0.0.1:1234/reloadgames 
