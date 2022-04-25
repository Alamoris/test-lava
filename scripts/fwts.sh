git clone https://github.com/ColinIanKing/fwts.git
cd fwts
apt -q update
apt -y -q install autoconf automake libglib2.0-dev libtool libpcre3-dev flex bison dkms libfdt-dev libbsd-dev
autoreconf -ivf
./configure
make
make install
lava-test-case hwts --shell fwts

